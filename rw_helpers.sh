#!/bin/bash

# Various helpers for sysadmin work.
#  Usage: source ./rw_helpers.sh


# Helper for container names. e.g. when working with the webserver container you can use:
#  web, w, or full container name.
# Use $RWPREFIX to customize container prefix.
get_container() {
    prefix="${RWPREFIX:-prod}"
    case "$1" in
        w | web | "$prefix-ropewiki_webserver-1")
            container="$prefix-ropewiki_webserver-1" ;;
        p | proxy | "$prefix-ropewiki_reverse_proxy-1")
            container="$prefix-ropewiki_reverse_proxy-1" ;;
        d | db | "$prefix-ropewiki_db-1")
            container="$prefix-ropewiki_db-1" ;;
        m | mail | "$prefix-ropewiki_mailserver-1")
            container="$prefix-ropewiki_mailserver-1" ;;
        b | backup | "$prefix-ropewiki_backup_manager-1")
            container="$prefix-ropewiki_backup_manager-1" ;;
        *)         echo "unknown container";;
    esac
}

# Enter a container
denter () {
  get_container $1
  dexec $container sh -c 'bash || sh'
}

# Execute a command in a container
dexec () {
  get_container $1
  local saved_state=$(stty -g 2>/dev/null)
  docker exec -it $container "${@:2}"
  local exit_code=$?
  [[ -n "$saved_state" ]] && stty "$saved_state" 2>/dev/null || stty sane 2>/dev/null
  return $exit_code
}

# Execute a database query
dbquery () {
  [[ -n "$RW_VERBOSE" ]] && echo $@ >&2
  dexec db mysql -uroot -p"$RW_ROOT_DB_PASSWORD" "$@"
}

# List all ropewiki users
rwusers () {
  dbquery "-s" "-N" "-e use ropewiki; SELECT STR_TO_DATE(user_registration, '%Y%m%d%H%i%s'), \
  user_name, user_real_name, user_email AS created_at FROM user ORDER BY user_registration DESC;"
}


detailedrwusers() {
  dbquery "-s" "-N" "-e use ropewiki; SELECT user_registration, user_name, user_real_name, \
  user_email, user_id, user_touched, user_email_authenticated, user_editcount \
  FROM user ORDER BY user_registration DESC;"
}

# Search for page title
findapage() {
    findinpage | grep -i $1
}

# Search for page content (if no search query provided returns all page names)
findinpage() {
  dbquery "-N" "-s" "-e" "use ropewiki;
SELECT
  CASE page_namespace
    WHEN 0 THEN REPLACE(page_title, '_', ' ')
    WHEN 1 THEN CONCAT('Talk:', REPLACE(page_title, '_', ' '))
    WHEN 2 THEN CONCAT('User:', REPLACE(page_title, '_', ' '))
    WHEN 3 THEN CONCAT('User talk:', REPLACE(page_title, '_', ' '))
    WHEN 4 THEN CONCAT('Project:', REPLACE(page_title, '_', ' '))
    WHEN 5 THEN CONCAT('Project talk:', REPLACE(page_title, '_', ' '))
    WHEN 6 THEN CONCAT('File:', REPLACE(page_title, '_', ' '))
    WHEN 7 THEN CONCAT('File talk:', REPLACE(page_title, '_', ' '))
    WHEN 8 THEN CONCAT('MediaWiki:', REPLACE(page_title, '_', ' '))
    WHEN 9 THEN CONCAT('MediaWiki talk:', REPLACE(page_title, '_', ' '))
    WHEN 10 THEN CONCAT('Template:', REPLACE(page_title, '_', ' '))
    WHEN 11 THEN CONCAT('Template talk:', REPLACE(page_title, '_', ' '))
    WHEN 12 THEN CONCAT('Help:', REPLACE(page_title, '_', ' '))
    WHEN 13 THEN CONCAT('Help talk:', REPLACE(page_title, '_', ' '))
    WHEN 14 THEN CONCAT('Category:', REPLACE(page_title, '_', ' '))
    WHEN 15 THEN CONCAT('Category talk:', REPLACE(page_title, '_', ' '))
    WHEN 102 THEN CONCAT('Property:', REPLACE(page_title, '_', ' '))
    WHEN 103 THEN CONCAT('Property talk:', REPLACE(page_title, '_', ' '))
    WHEN 106 THEN CONCAT('Form:', REPLACE(page_title, '_', ' '))
    WHEN 107 THEN CONCAT('Form talk:', REPLACE(page_title, '_', ' '))
    WHEN 108 THEN CONCAT('Concept:', REPLACE(page_title, '_', ' '))
    WHEN 109 THEN CONCAT('Concept talk:', REPLACE(page_title, '_', ' '))
    WHEN 170 THEN CONCAT('Filter:', REPLACE(page_title, '_', ' '))
    WHEN 171 THEN CONCAT('Filter talk:', REPLACE(page_title, '_', ' '))
    WHEN 190 THEN CONCAT('Conditions:', REPLACE(page_title, '_', ' '))
    WHEN 191 THEN CONCAT('Conditions talk:', REPLACE(page_title, '_', ' '))
    WHEN 192 THEN CONCAT('Preparation:', REPLACE(page_title, '_', ' '))
    WHEN 193 THEN CONCAT('Preparation talk:', REPLACE(page_title, '_', ' '))
    WHEN 194 THEN CONCAT('Incidents:', REPLACE(page_title, '_', ' '))
    WHEN 195 THEN CONCAT('Incidents talk:', REPLACE(page_title, '_', ' '))
    WHEN 196 THEN CONCAT('Votes:', REPLACE(page_title, '_', ' '))
    WHEN 197 THEN CONCAT('Votes talk:', REPLACE(page_title, '_', ' '))
    WHEN 198 THEN CONCAT('Events:', REPLACE(page_title, '_', ' '))
    WHEN 199 THEN CONCAT('Events talk:', REPLACE(page_title, '_', ' '))
    WHEN 200 THEN CONCAT('Lists:', REPLACE(page_title, '_', ' '))
    WHEN 201 THEN CONCAT('Lists talk:', REPLACE(page_title, '_', ' '))
    WHEN 828 THEN CONCAT('Module:', REPLACE(page_title, '_', ' '))
    WHEN 829 THEN CONCAT('Module talk:', REPLACE(page_title, '_', ' '))
    WHEN 3000 THEN CONCAT('Topo:', REPLACE(page_title, '_', ' '))
    WHEN 3001 THEN CONCAT('Topo talk:', REPLACE(page_title, '_', ' '))
    ELSE CONCAT('NS', page_namespace, ':', REPLACE(page_title, '_', ' '))
  END AS full_title
FROM page
JOIN revision ON page.page_latest = revision.rev_id
JOIN slots ON slots.slot_revision_id = revision.rev_id
JOIN slot_roles ON slots.slot_role_id = slot_roles.role_id AND slot_roles.role_name = 'main'
JOIN content ON slots.slot_content_id = content.content_id
JOIN text ON LEFT(content.content_address,3) = 'tt:' AND text.old_id = CAST(SUBSTRING(content.content_address,4) AS UNSIGNED)
WHERE text.old_text LIKE '%$@%';" | grep -sv "interface can be insecure"
}

