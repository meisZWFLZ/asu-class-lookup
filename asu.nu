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

# Fetches detailed info about reserved seats, including the date they are unreserved.
# Seems unnecessary, as after this date, the number of reserved seats is set to 1.
export def "api fetch reserved_seats" [params: record] {
  let endpoint = "search/reservedseatsadditionalinfo"
  let renaming = {
    term: term,
    class_number: classNbr,
    academic_career: classNbr,
    course_id: crseId,
    course_offer: crseOfferNbr,
    class_section: classSection,
    session: sessionCode
  }
  api fetch $endpoint ($params | select ...($renaming | columns)| rename --column $renaming)
}
def beautify_class_data [] {
  # TODO: look into moving the logic for processing this config and using it somewhere else
  # TODO: perhaps embed the filters inside the config as closures
  let key_mapping_config: list<record<old_key, new_key: string, drop: bool, expect: bool>> = {
    CLAS.CLASSNBR: "class_number",
    CLAS.INSTRUCTORSLIST: "instructor",
    CLAS.CAMPUS: "campus",
    CLAS.STARTTIME: "start_time",
    CLAS.ENDTIME: "end_time",
    SUBJECTNUMBER: "subject_number", # Unknown for class search command otherwise
    DAYLIST: "days",
    CLAS.COMPONENTPRIMARY: "component",
    seatInfo: "seats",
    CLAS.STARTDATE: "start_date",
    CLAS.ENDDATE: "end_date",
    GSGOLD: "general_studies_gold",
    # Used for reserved seats endpoint
    CLAS.CRSEID: "course_id",
    CLAS.CRSEOFFERNBR: { new_key: "course_offer", drop: true },
    CLAS.CLASSSECTION: "class_section",
    CLAS.SESSIONCODE: "session",
    CLAS.ACADCAREER: { new_key: "academic_career", drop: true },
    reservedSeatsInfo: { new_key: "reserved_seats_info", drop: true},
    CLAS.STRM: { new_key: "term", drop: true },
    # Mostly useless
    CLAS.COURSETITLE_LONG: "title",
    CLAS.CLASSDESCR: "description",
    NOTES: "notes",
    # Added later
    catalog_link: { expect: false },
    add_to_cart_link: { expect: false },
  } | items { |key, value| 
    if (($value | describe -d | get type) == record) { 
      $value | default $key new_key
    } else { 
      {new_key: $value}
    } 
    | default false drop 
    | default true expect 
    | insert old_key { |row|
      if ($row.raw_old_key? | default false) {
        $key 
      } else {
        $key | split row "." | into cell-path
      }
    }
  }
  let input_key_mapping = $key_mapping_config | where expect == true;
  let input_key_mapping_record =  $input_key_mapping | each { [
      ($in.old_key | split cell-path | get value | skip 0 | str join "."), 
      $in.new_key
    ] 
  } | into record;
  let final_keys = $key_mapping_config | where drop == false | get new_key;
  $in
  | select --optional ...($input_key_mapping | get old_key)
  | rename --column $input_key_mapping_record
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
    let all_available = $seats.ENRL_CAP - $seats.ENRL_TOT
    
    let available_reserved = if $all_available == 0 {
      0
    } else if $reserved != null {
      $reserved | each { |r| [($r.ENRL_CAP - $r.ENRL_TOT),0] | math max } | math sum
    } else {
      0
    }
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
  | select --optional ...$final_keys
} 

export def "course search" [subject number --after: string --before: string --available (-a)] {
  api fetch course $subject $number
  | beautify_class_data
  | reject "subject_number"
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
  | beautify_class_data
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