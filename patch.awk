#!/usr/bin/awk -f

# Insert portal path inbetween a|b and remainder of path
function insert_portal_path(path) {
  before = substr(path, 0, 2)
  after = substr(path, 3)

  return before portal_path_addition after
}

# Find beginning of diff block and update a|b paths with additional path for liferay-portal-ee
/^diff --git a\/.* b\/.*$/ {
  aPath = insert_portal_path($3)
  bPath = insert_portal_path($4)

  # print NR": " $0 " (" NF ") "
  print NR":" $1 " " $2 " " aPath " " bPath
}

# Finds file subtraction diffs and update the path of that line and the next line if the next line is a file addition diff
/^--- (a\/.*)|(\/dev\/null)$/ {
  if (match($0, /^--- a\/.*/)) {
    # sub(/^a\//, "a/" PORTAL_ROUTE_ADDITION, $2)

    print NR ":" $1 " " insert_portal_path($2)
  }

  getline

  # Insert PORTAL_ROUTE_ADDITION inbetween
  if (match($0, /^+++ b\/.*/)) {
    # sub(/^b\//, "b/" PORTAL_ROUTE_ADDITION, $2)

    print NR ":" $1 " " insert_portal_path($2)
  }
}
