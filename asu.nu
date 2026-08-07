#!/usr/bin/env nu

def "api fetch" [endpoint params: record] {
  let base_url = "https://eadvs-cscc-catalog-api.apps.asu.edu/catalog-microservices/api/v1";
  http get --headers {authorization: "Bearer null"} (
    $base_url + "/" + $endpoint + "?" + ($params | url build-query)
  )
}
def "api fetch class search" [params: record] {
  # TODO: don't hardcode the term
  let default_params = {term: 2267, refine: "Y", campusOrOnlineSelection: "C"};
  let params = $default_params | merge $params;
  let res = api fetch "search/classes" $params
  let total_num = $res | get total.value;
  let class_num = ($res.classes | length);
  if $total_num == 0 {
    error make {msg:  $"No classes found!" }
  } else if $total_num != $class_num {
    error make {msg:  $"Got ($class_num)/($total_num) classes!" }
  } else {
    $res | get classes
  }
}

# Fetches the raw data for all the classes associated with a course
export def "api fetch course" [subject number] {
  api fetch class search {subject: $subject, catalogNbr: $number}
}

# Fetches the raw data for a specific class given its class number
export def "api fetch class_nbr" [class_nbr] {
  api fetch class search {classNbr: $class_nbr}
}
def beautify_data [] {
  let header_mapping = {
    "CLASSNBR": "class_number",
    "INSTRUCTORSLIST": "instructor",
    "CAMPUS": "campus",
    "STARTTIME": "start_time",
    "ENDTIME": "end_time",
    "DAYLIST": "days",
    "COMPONENTPRIMARY": "component",
    "seatInfo": "seats",
    "STARTDATE": "start_date",
    "ENDDATE": "end_date",
    "GSGOLD": "general_studies_gold",
    # Mostly useless
    "SESSIONCODE": "session",
    "COURSETITLE_LONG": "title",
    "CRSEID": "course_id",
    "CLASSSECTION": "class_section",
    "CLASSDESCR": "description",
    "NOTES": "notes",
    # Removed later
    "reservedSeatsInfo": "reserved_seats_info",
    "STRM": "term",
  }
  let final_headers = $header_mapping | values | where $it != reserved_seats_info | append "catalog_link" | append "add_to_cart_link";
  $in 
  | flatten CLAS
  | select --optional ...($header_mapping | columns)
  | rename --column $header_mapping
  | update instructor { 
    if ($in | length) == 1 { 
      $in.0
    } else if ($in | length) == 0 { 
      "" 
    } else { 
      $in
    }
  }
  | update seats { |row| 
    let seats = $row.seats
    let reserved = $row.reserved_seats_info
    let available_reserved = if $reserved != null {
      $reserved | each { |r| [($r.ENRL_CAP - $r.ENRL_TOT),0] | math max } | math sum
    } else {
      0
    }
    let all_available = $seats.ENRL_CAP - $seats.ENRL_TOT
    {
      "max": $seats.ENRL_CAP,
      "all_available": $all_available,
      "available": ($all_available - $available_reserved),
      "reserved": $reserved,
    }
  }
  | insert add_to_cart_link { |row| 
    $"https://go.oasis.asu.edu/addclass?STRM=($row.term)&ASU_CLASS_NBR=($row.class_number)"
  }
  | insert catalog_link { |row| 
    $"https://catalog.apps.asu.edu/catalog/classes/classlist?keywords=($row.class_number)&searchType=all&term=2267#detailsOpen=($row.class_number)-($row.course_id)"
  }
  | update days { $in.0 | split words | each {str trim} | str join "," }
  | select --optional ...$final_headers
} 

export def "course search" [subject number --after: string --before: string --available (-a)] {
  api fetch course $subject $number
  | beautify_data
  | do { 
    if $available {
      $in | where { $in.seats.available > 0 }
    } else {
      $in
    }
  }
  | do { 
    if $after != null {
      let after_time = $after | into datetime;
      $in | where { ($in.start_time | into datetime) >= $after_time}
    } else {
      $in
    }
  }
  | do { 
    if $before != null {
      let before_time = $before | into datetime;
      $in | where { ($in.end_time | into datetime) <= $before_time}
    } else {
      $in
    }
  }
}

export def "class search" [class_nbr --available (-a)] {
  api fetch class_nbr $class_nbr
  | beautify_data
  | do { 
    if $available {
      $in | where { $in.seats.available > 0 }
    } else {
      $in
    }
  }
}

export def class_checker_pingbot [--loop] {
  use std/log;
  while true {
    try {
      log debug "Checking classes for available seats..."
      let classes = ["60296", "60299", "63576"]
      let user_id = "513806934512762882"
      let available = $classes | each { class search $in -a } | flatten
      if ($available | length) > 0 {
        log info "Found available seats!"
        let msg = "Found available seats!\n" + (
          $available | each { 
            $"($in.class_number) has ($in.seats.available) available seats! Details:\n" + (
              $in | to nuon
            ) 
          } | str join "\n"
        );
        asu-class-pingbot say $user_id $msg
      } else {
        log debug "No available seats found."
      }
    } catch { |e|
      if $loop {
        # If in loop mode, log the error and continue
        log error $"Error occurred while checking classes: ($e)"
      } else {
        # If not in loop mode, forward the error
        error make $e
      }
    }
    if not $loop {
      break
    }
    sleep 5min # Check every 5 minutes
  }
}

export def "main" [] {
  class_checker_pingbot --loop
}