----User Table 

CREATE TABLE users (
    id BIGINT PRIMARY KEY,               -- maps to QuickBooks user ID
    first_name TEXT,
    last_name TEXT,
    group_id BIGINT,
    active BOOLEAN,
    employee_number BIGINT,
    salaried BOOLEAN,
    exempt BOOLEAN,
    username TEXT,
    email TEXT,
    email_verified BOOLEAN,
    payroll_id TEXT,
    mobile_number TEXT,
    hire_date DATE,
    term_date DATE,
    last_modified TIMESTAMP WITH TIME ZONE,
    last_active TIMESTAMP WITH TIME ZONE,
    created TIMESTAMP WITH TIME ZONE,
    client_url TEXT,
    company_name TEXT,
    profile_image_url TEXT,
    display_name TEXT,
    submitted_to DATE,
    approved_to DATE,
    require_password_change BOOLEAN,
    pay_rate NUMERIC,
    pay_interval TEXT,                   -- e.g., "hour"
    
    -- Permissions (flattened JSONB for flexibility)
    permissions JSONB,

    -- PTO balances (can be dynamic keys, so JSONB is better)
    pto_balances JSONB,

    -- Manager groups array
    manager_of_group_ids BIGINT[],

    -- Custom fields (if needed, keep JSONB for flexibility)
    customfields JSONB
);


---Timesheet 

CREATE TABLE timesheets (
    id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    jobcode_id BIGINT NOT NULL REFERENCES jobcodes(id) ON DELETE CASCADE,

    start TEXT,
    "end" TEXT,
    duration BIGINT,
    "date" DATE,
    tz INTEGER,
    tz_str TEXT,
    type TEXT,
    location TEXT,
    on_the_clock BOOLEAN,
    locked INTEGER,
    notes TEXT,

    customfields JSONB,
    last_modified TIMESTAMP WITH TIME ZONE
);


---files

CREATE TABLE files (
    id BIGINT PRIMARY KEY,
    uploaded_by_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
    file_name TEXT NOT NULL,
    active BOOLEAN,
    size BIGINT,
    last_modified TIMESTAMP WITH TIME ZONE,
    created TIMESTAMP WITH TIME ZONE,
    file_description TEXT
);

CREATE TABLE timesheet_files (
    timesheet_id BIGINT NOT NULL REFERENCES timesheets(id) ON DELETE CASCADE,
    file_id BIGINT NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    PRIMARY KEY (timesheet_id, file_id)
);




--- customer (jobcodes)---------------


CREATE TABLE jobcodes (
    id BIGINT PRIMARY KEY,
    parent_id BIGINT REFERENCES jobcodes(id) ON DELETE SET NULL,
    assigned_to_all BOOLEAN,
    billable BOOLEAN,
    active BOOLEAN,
    type TEXT,
    has_children BOOLEAN,
    billable_rate NUMERIC(12,2),
    short_code TEXT,
    name TEXT NOT NULL,
    last_modified TIMESTAMP WITH TIME ZONE,
    created TIMESTAMP WITH TIME ZONE,
    filtered_customfielditems TEXT,
    connect_with_quickbooks BOOLEAN
);


---

CREATE TABLE jobcode_required_customfields (
    jobcode_id BIGINT NOT NULL REFERENCES jobcodes(id) ON DELETE CASCADE,
    customfield_id BIGINT NOT NULL,
    PRIMARY KEY (jobcode_id, customfield_id)
);
------------------------


--- projects 

CREATE TABLE projects (
    id BIGINT PRIMARY KEY,
    jobcode_id BIGINT NOT NULL REFERENCES jobcodes(id) ON DELETE CASCADE,
    parent_jobcode_id BIGINT REFERENCES jobcodes(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    status TEXT CHECK (status IN ('not_started', 'in_progress', 'completed', 'on_hold')) DEFAULT 'not_started',
    description TEXT,
    start_date TIMESTAMP WITH TIME ZONE,
    due_date TIMESTAMP WITH TIME ZONE,
    completed_date TIMESTAMP WITH TIME ZONE,
    active BOOLEAN,
    last_modified TIMESTAMP WITH TIME ZONE,
    created TIMESTAMP WITH TIME ZONE,
    linked_objects JSONB DEFAULT '{}'::jsonb
);

-----


-----

CREATE TABLE locations (
    id BIGINT PRIMARY KEY,
    addr1 TEXT,
    addr2 TEXT,
    city TEXT,
    state TEXT,
    zip TEXT,
    country TEXT,
    formatted_address TEXT,
    active BOOLEAN,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    place_id TEXT,
    place_id_hash TEXT,
    label TEXT,
    notes TEXT,
    geocoding_status TEXT CHECK (geocoding_status IN ('pending','in_progress','complete','failed')),
    created TIMESTAMP WITH TIME ZONE,
    last_modified TIMESTAMP WITH TIME ZONE,
    geofence_config_id BIGINT,
    linked_objects JSONB DEFAULT '{}'::jsonb
);

----
---- location map 

CREATE TABLE location_map (
    id BIGINT PRIMARY KEY,
    x_table TEXT NOT NULL,               -- e.g. "job_codes"
    x_id BIGINT NOT NULL,                -- foreign key value in x_table
    location_id BIGINT NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
    created TIMESTAMP WITH TIME ZONE,
    last_modified TIMESTAMP WITH TIME ZONE
);



--------------

-- CUSTOMFIELD VALUES PER TIMESHEET (link table)
CREATE TABLE timesheet_customfield_values (
    timesheet_id BIGINT REFERENCES timesheets(id) ON DELETE CASCADE,
    customfield_id BIGINT REFERENCES custom_fields(id) ON DELETE CASCADE,
    value TEXT,
    PRIMARY KEY (timesheet_id, customfield_id)
);



CREATE TABLE custom_fields (
    id BIGINT PRIMARY KEY,              -- matches "id"
    active BOOLEAN NOT NULL,            -- true/false
    required BOOLEAN NOT NULL,          -- required field
    applies_to TEXT,                    -- e.g. "timesheet"
    type TEXT,                          -- e.g. "managed-list"
    short_code TEXT,                    -- e.g. "e"
    regex_filter TEXT,                  -- regex string (empty allowed)
    name TEXT NOT NULL,                 -- field name
    last_modified TIMESTAMPTZ,          -- last modified timestamp
    created TIMESTAMPTZ,                -- created timestamp
    ui_preference TEXT,                 -- e.g. "drop_down"
    required_customfields BIGINT[] DEFAULT '{}', -- array of IDs
    show_to_all BOOLEAN DEFAULT false   -- flag
);


-------


CREATE TABLE custom_field_options (
    id BIGINT PRIMARY KEY,                   -- unique ID for option
    customfield_id BIGINT NOT NULL,          -- FK -> custom_fields.id
    active BOOLEAN NOT NULL,                 -- true/false
    short_code TEXT,                         -- code (can be empty string)
    name TEXT NOT NULL,                      -- option name (e.g. "Bazooka")
    last_modified TIMESTAMPTZ,               -- last modified
    required_customfields BIGINT[] DEFAULT '{}', -- array of IDs
    CONSTRAINT fk_customfield
        FOREIGN KEY (customfield_id)
        REFERENCES custom_fields(id)
        ON DELETE CASCADE
);