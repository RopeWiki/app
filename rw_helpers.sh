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
  docker exec -it $container "${@:2}"
}

# Execute a database query
dbquery () {
  echo $@ >&2
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
# TODO: patch query post MW 1.35 upgrade
findinpage() {
  dbquery "-N" "-s" "-e use ropewiki;

  SELECT
    CASE page_namespace
      WHEN 0 THEN page_title
      WHEN 1 THEN CONCAT('Talk:', page_title)
      WHEN 2 THEN CONCAT('User:', page_title)
      WHEN 3 THEN CONCAT('User talk:', page_title)
      WHEN 4 THEN CONCAT('Project:', page_title)
      WHEN 5 THEN CONCAT('Project talk:', page_title)
      WHEN 6 THEN CONCAT('File:', page_title)
      WHEN 7 THEN CONCAT('File talk:', page_title)
      WHEN 8 THEN CONCAT('MediaWiki:', page_title)
      WHEN 9 THEN CONCAT('MediaWiki talk:', page_title)
      WHEN 10 THEN CONCAT('Template:', page_title)
      WHEN 11 THEN CONCAT('Template talk:', page_title)
      WHEN 12 THEN CONCAT('Help:', page_title)
      WHEN 13 THEN CONCAT('Help talk:', page_title)
      WHEN 14 THEN CONCAT('Category:', page_title)
      WHEN 15 THEN CONCAT('Category talk:', page_title)
      WHEN 102 THEN CONCAT('Property:', page_title)
      WHEN 103 THEN CONCAT('Property talk:', page_title)
      WHEN 106 THEN CONCAT('Form:', page_title)
      WHEN 107 THEN CONCAT('Form talk:', page_title)
      WHEN 108 THEN CONCAT('Concept:', page_title)
      WHEN 109 THEN CONCAT('Concept talk:', page_title)
      WHEN 170 THEN CONCAT('Filter:', page_title)
      WHEN 171 THEN CONCAT('Filter talk:', page_title)
      WHEN 190 THEN CONCAT('Conditions:', page_title)
      WHEN 191 THEN CONCAT('Conditions talk:', page_title)
      WHEN 192 THEN CONCAT('Preparation:', page_title)
      WHEN 193 THEN CONCAT('Preparation talk:', page_title)
      WHEN 194 THEN CONCAT('Incidents:', page_title)
      WHEN 195 THEN CONCAT('Incidents talk:', page_title)
      WHEN 196 THEN CONCAT('Votes:', page_title)
      WHEN 197 THEN CONCAT('Votes talk:', page_title)
      WHEN 198 THEN CONCAT('Events:', page_title)
      WHEN 199 THEN CONCAT('Events talk:', page_title)
      WHEN 200 THEN CONCAT('Lists:', page_title)
      WHEN 201 THEN CONCAT('Lists talk:', page_title)
      WHEN 828 THEN CONCAT('Module:', page_title)
      WHEN 829 THEN CONCAT('Module talk:', page_title)
      ELSE CONCAT('NS', page_namespace, ':', page_title)
    END AS full_title
  FROM page
  JOIN revision ON page.page_latest = revision.rev_id
  JOIN text ON revision.rev_text_id = text.old_id
  WHERE text.old_text LIKE '%$@%';" | grep -sv "interface can be insecure"
}

