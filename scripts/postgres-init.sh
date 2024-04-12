#!/usr/bin/env bash
set -Eeo pipefail

# define color output
BLACK='\033[0;30m'     
DARKGRAY='\033[1;30m'
RED='\033[0;31m'     
LIGHTRED='\033[1;31m'
GREEN='\033[0;32m'     
LIGHTGREEN='\033[1;32m'
ORANGE='\033[0;33m'           
YELLOW='\033[1;33m'
BLUE='\033[0;34m'     
LIGHTBLUE='\033[1;34m'
PURPLE='\033[0;35m'     
LIGHTPURPLE='\033[1;35m'
CYAN='\033[0;36m'     
LIGHTCYAN='\033[1;36m'
LIGHTGRAY='\033[0;37m'      
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# check to see if this file is being run or sourced from another script
_is_sourced() {
	# https://unix.stackexchange.com/a/215279
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}



_main() {


echo 
echo -e "${LIGHTBLUE}[postgres-init.sh] init kozmo_builder & kozmo_supervisor database.${NC}"
echo 


# check if postgres really starting
RETRIES=5
until psql -U postgres postgres -c "select 1" > /dev/null 2>&1 || [ $RETRIES -eq 0 ]; do
  echo "Waiting for postgres server, $((RETRIES--)) remaining attempts..."
  sleep 5
done

if [ $RETRIES -eq 0 ]; then
    echo -e "${RED}[FATAL] CAN NOT CONNECT TO POSTGERS DATABASE, PLEASE CHECK YOUR DATABASE INIT STATUS AND FOLDER PERMISSIONS.${NC}"
    return 1
fi

# ok, init database and table.
echo 
echo -e "${LIGHTBLUE}init database.${NC}"
echo 
psql -U postgres postgres <<EOF

-- init kozmo_builder


create database kozmo_builder;

\c kozmo_builder;

create user kozmo_builder with encrypted password 'kozmo2022';

grant all privileges on database kozmo_builder to kozmo_builder;

CREATE EXTENSION pg_trgm;

CREATE EXTENSION btree_gin;

-- apps
create table if not exists apps (
    id                      bigserial                       not null primary key,
    uid                     uuid default gen_random_uuid()  not null,
    team_id                 bigserial                       not null, 
    name                    varchar(200)                    not null,
    release_version         bigint                          not null,
    mainline_version        bigint                          not null,
    config                  jsonb,
    created_at              timestamp                       not null,
    created_by              bigint                          not null,
    updated_at              timestamp                       not null,
    updated_by              bigint                          not null,
    edited_by               jsonb

);

alter table apps owner to kozmo_builder;

-- app_snapshots
create table if not exists app_snapshots (
    id                      bigserial                       not null primary key,
    uid                     uuid default gen_random_uuid()  not null,
    team_id                 bigserial                       not null, 
    app_ref_id              bigserial                       not null,
    target_version          bigint                          not null,
    trigger_mode            smallint                        not null,
    modify_history          jsonb,                           
    created_at              timestamp                       not null
);

alter table app_snapshots owner to kozmo_builder;

-- resource
create table if not exists resources (
    id                      bigserial                       not null primary key,
    uid                     uuid default gen_random_uuid()  not null,
    team_id                 bigserial                       not null, 
    name                    varchar(200)                    not null,
    type                    smallint                        not null,
    options                 jsonb,
    created_at              timestamp                       not null,
    created_by              bigint                          not null,
    updated_at              timestamp                       not null,
    updated_by              bigint                          not null
);

alter table resources owner to kozmo_builder;

-- actions
create table if not exists actions (
    id                      bigserial                       not null primary key,
    uid                     uuid default gen_random_uuid()  not null,
    team_id                 bigserial                       not null, 
    version                 bigint                          not null,
    resource_ref_id         bigint                          not null,
    app_ref_id              bigint                          not null,
    name                    varchar(255)                    not null,
    type                    smallint                        not null,
    transformer             jsonb                           not null,
    trigger_mode            varchar(16)                     not null,
    template                jsonb,
    config                  jsonb,
    created_at              timestamp                       not null,
    created_by              bigint                          not null,
    updated_at              timestamp                       not null,
    updated_by              bigint                          not null
);

create index if not exists actions_at_apprefid_and_version on actions (app_ref_id, version);
alter table actions owner to kozmo_builder;


ALTER TABLE actions DROP CONSTRAINT IF EXISTS actions_displayname_constrainte,
ADD CONSTRAINT actions_displayname_constrainte UNIQUE (version, app_ref_id, name);

-- tree_states, component tree_states
create table if not exists tree_states (
    id                      bigserial                       not null primary key,
    uid                     uuid default gen_random_uuid()  not null,
    team_id                 bigserial                       not null, 
    state_type              smallint                        not null,
    parent_node_ref_id      bigint                          not null,
    children_node_ref_ids   jsonb,
    app_ref_id              bigint                          not null,
    version                 bigint                          not null,
    name                    text                            not null,
    content                 jsonb                           not null,
    created_at              timestamp                       not null,
    created_by              bigint                          not null,
    updated_at              timestamp                       not null,
    updated_by              bigint                          not null
);

CREATE INDEX tree_states_at_apprefid_and_version_and_statetype ON tree_states (app_ref_id, version, state_type);
CREATE INDEX tree_states_at_parentnoderefid ON tree_states (parent_node_ref_id);
CREATE INDEX tree_states_at_childrennoderefids ON tree_states (children_node_ref_ids);
CREATE INDEX tree_states_with_gin_at_childrennoderefids ON tree_states USING gin (children_node_ref_ids);
CREATE INDEX tree_states_with_gin_at_name ON tree_states USING gin (name);
CREATE INDEX tree_states_with_fulltextgin_at_name ON tree_states USING gin (to_tsvector('english', name));

ALTER TABLE tree_states DROP CONSTRAINT IF EXISTS tree_states_displayname_constrainte,
ADD CONSTRAINT tree_states_displayname_constrainte UNIQUE (version, app_ref_id, name);

alter table tree_states owner to kozmo_builder;

-- kv_states, component kv_states
create table if not exists kv_states (
    id                      bigserial                       not null primary key,
    uid                     uuid default gen_random_uuid()  not null,
    team_id                 bigserial                       not null, 
    state_type              smallint                        not null,
    app_ref_id              bigint                          not null,
    version                 bigint                          not null,
    key                     text                            not null,
    value                   jsonb                           not null,
    created_at              timestamp                       not null,
    created_by              bigint                          not null,
    updated_at              timestamp                       not null,
    updated_by              bigint                          not null
);

CREATE INDEX kv_states_at_apprefid_and_version_and_statetype ON kv_states (app_ref_id, version, state_type);
CREATE INDEX kv_states_with_gin_at_key ON kv_states USING gin (key);
CREATE INDEX kv_states_with_fulltextgin_at_key ON kv_states USING gin (to_tsvector('english', key));
ALTER TABLE kv_states DROP CONSTRAINT IF EXISTS kv_states_displayname_constrainte,
ADD CONSTRAINT kv_states_displayname_constrainte UNIQUE (version, app_ref_id, key);

alter table kv_states owner to kozmo_builder;

-- set_states, component set_states
create table if not exists set_states (
    id                      bigserial                       not null primary key,
    uid                     uuid default gen_random_uuid()  not null,
    team_id                 bigserial                       not null, 
    state_type              smallint                        not null,
    app_ref_id              bigint                          not null,
    version                 bigint                          not null,
    value                   text                            not null,
    created_at              timestamp                       not null,
    created_by              bigint                          not null,
    updated_at              timestamp                       not null,
    updated_by              bigint                          not null
);

CREATE INDEX set_states_at_apprefid_and_version_and_statetype ON set_states (app_ref_id, version, state_type);
CREATE INDEX set_states_with_gin_at_value ON set_states USING gin (value);
CREATE INDEX set_states_with_fulltextgin_at_value ON set_states USING gin (to_tsvector('english', value));

ALTER TABLE set_states DROP CONSTRAINT IF EXISTS set_states_displayname_constrainte,
ADD CONSTRAINT set_states_displayname_constrainte UNIQUE (version, app_ref_id, value);

alter table set_states owner to kozmo_builder;



-- init kozmo_supervisor


-- init
create database kozmo_supervisor;
\c kozmo_supervisor;
create user kozmo_supervisor with encrypted password 'kozmo2022';
grant all privileges on database kozmo_supervisor to kozmo_supervisor;
CREATE EXTENSION pg_trgm;
CREATE EXTENSION btree_gin;


/**
 * TEAM Management
 *
 *
 */

-- teams
create table if not exists teams (
    id                       bigserial                               not null primary key,
    uid                      uuid         default gen_random_uuid()  not null,
    name                     varchar(255)                            not null,
    identifier               varchar(255) unique                     not null,
    icon                     varchar(255)                            not null,
    permission               jsonb                                   not null,
    created_at               timestamp                               not null,
    updated_at               timestamp                               not null,
    constraint               teams_ukey unique (id, uid)
);

CREATE INDEX teams_uid ON teams (uid);

alter table
    teams owner to kozmo_supervisor;

-- users
create table if not exists users (
    id                       bigserial                         not null primary key,
    uid                      uuid    default gen_random_uuid() not null,
    nickname                 varchar(15)                       not null, 
    password_digest          varchar(60)                       not null,
    email                    varchar(255)                      not null,
    avatar                   varchar(255)                      not null,
    sso_config               jsonb                             not null, 
    customization            jsonb                             not null, 
    created_at               timestamp                         not null,
    updated_at               timestamp                         not null,
    constraint               users_ukey2 unique (id, uid),
    constraint               users_email unique (email)
);

CREATE INDEX users_uid ON users (uid);
CREATE INDEX users_nickname_fulltext ON users USING gin (to_tsvector('english', nickname));
CREATE INDEX users_email_fulltext ON users USING gin (to_tsvector('english', email));

alter table
    users owner to kozmo_supervisor;

-- team_members
create table if not exists team_members (
    id                       bigserial                         not null primary key,
    team_id                  bigserial                         not null,
    user_id                  bigserial                         not null,  
    user_role                smallint                          not null, 
    permission               jsonb                            ,         
    status                   smallint                          not null, 
    created_at               timestamp                         not null,
    updated_at               timestamp                         not null
);

CREATE INDEX team_members_team_and_user_id ON team_members (team_id, user_id);

alter table
    team_members owner to kozmo_supervisor;

-- invites
create table if not exists invites (
    id                       bigserial                            not null primary key,
    uid                      uuid       default gen_random_uuid() not null, 
    category                 smallint                             not null,  
    team_id                  bigserial                            not null,
    team_member_id           bigserial                            not null,  
    email                    varchar(255)                        ,          
    email_status             boolean default false                not null,  
    user_role                smallint                             not null,  
    status                   smallint                             not null,  
    created_at               timestamp                            not null,
    updated_at               timestamp                            not null,
    constraint               invite_ukey unique (id, uid)
);

CREATE INDEX invites_uid ON invites (uid);
CREATE INDEX invites_email ON invites (email);
CREATE INDEX invites_user_role ON invites (user_role);

alter table
    invites owner to kozmo_supervisor;


/**
 * Role Management
 *
 *
 */

-- roles
create table if not exists roles (
    id                       bigserial                            not null primary key,
    uid                      uuid       default gen_random_uuid() not null,
    name                     varchar(255)                         not null,         
    team_id                  bigserial                            not null, 
    permissions              jsonb                                not null,
    created_at               timestamp                            not null,
    updated_at               timestamp                            not null
);
CREATE INDEX roles_id_team_id ON roles(id, team_id);
CREATE INDEX roles_name_fulltext ON roles USING gin (to_tsvector('english', name));
alter table roles owner to kozmo_supervisor;

-- user_role_relations
create table if not exists user_role_relations (
    id                       bigserial                            not null primary key,
    uid                      uuid       default gen_random_uuid() not null,
    team_id                  bigserial                            not null, 
    role_id                  bigserial                            not null, 
    user_id                  bigserial                            not null,
    created_at               timestamp                            not null,
    updated_at               timestamp                            not null
);
CREATE INDEX user_role_relations_team_role_user_id ON user_role_relations(team_id, role_id, user_id);
alter table user_role_relations owner to kozmo_supervisor;

-- unit_role_relations
create table if not exists unit_role_relations (
    id                       bigserial                            not null primary key,
    uid                      uuid       default gen_random_uuid() not null,
    team_id                  bigserial                            not null, 
    role_id                  bigserial                            not null, 
    unit_id                  bigserial                            not null,
    unit_type                smallint                             not null,
    created_at               timestamp                            not null,
    updated_at               timestamp                            not null
);
CREATE INDEX unit_role_relations_team_role_unit_id_and_unit_type ON unit_role_relations(team_id, role_id, unit_id, unit_type);
alter table unit_role_relations owner to kozmo_supervisor;


/**
 * DDL
 *
 *
 */

INSERT INTO teams ( 
    id, uid, name, identifier, icon, permission, created_at, updated_at
) SELECT
    0, '83cfb484-0a3f-4bfd-aab3-70432d021cab', 'my-team'    , '0'  , 'https://cdn.kozmoai.com/email-template/people.png', '{"allowEditorInvite": true, "allowViewerInvite": true, "inviteLinkEnabled": true, "allowEditorManageTeamMember": true, "allowViewerManageTeamMember": true, "blockRegister": false}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
WHERE NOT EXISTS (
    SELECT id FROM teams WHERE id = 0
);


INSERT INTO users (
    uid, nickname, password_digest, email, avatar, sso_config, customization, created_at, updated_at
) SELECT 
    '158504d6-a47d-43a0-879e-79a57981cecc', 
    'root', 
    '\$2a\$10\$iVIxJRgy1K6RIV389AYg3OiMIbuDyuCIja1xrHGkCljdg/6gdmWXa'::text, 
    'root', 
    '', 
    '{"default": ""}', 
    '{"Language": "en-US", "IsSubscribed": false}', 
    CURRENT_TIMESTAMP, 
    CURRENT_TIMESTAMP
WHERE NOT EXISTS (
    SELECT nickname FROM users WHERE nickname = 'root'
);

INSERT INTO team_members (
    team_id, user_id, user_role, permission, status, created_at, updated_at   
) SELECT       
    0, root_id, 1, '{"Config": 0}', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
FROM (select id as root_id from users where nickname='root') AS t1
WHERE NOT EXISTS (
    SELECT id FROM team_members WHERE team_id = 0 AND user_role = 1
);



EOF

echo
echo -e "${LIGHTBLUE}[postgres-init.sh] init kozmo_builder database done.${NC}"
echo

}



if ! _is_sourced; then
	_main "$@"
fi
