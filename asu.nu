#!/usr/bin/env nu

const default_term = 2271

def "api fetch" [endpoint params: record] {
  let base_url = "https://eadvs-cscc-catalog-api.apps.asu.edu/catalog-microservices/api/v1";
  http get --headers {authorization: "Bearer null"} (
    $base_url + "/" + $endpoint + "?" + ($params | url build-query)
  )
}
def "api fetch class search" [params: record, --term=$default_term] {
  # TODO: don't hardcode the term
  let default_params = {term: 2271, refine: "Y", campusOrOnlineSelection: "C"};
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
    $"https://catalog.apps.asu.edu/catalog/classes/classlist?keywords=($row.class_number)&searchType=all&term=($row.term)#detailsOpen=($row.class_number)-($row.course_id)"
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

export def class_checker_pingbot [--loop --state-file=./state/state.json] {
  use std/log;
  
  # TODO: make this configurable
  let owner_id = "513806934512762882"
  let class_numbers = [
    "15780", # EEE 202: Marnie Wong
    "11346", # EEE 202: Staff (test class)
  ]
  let max_error_count = 5
  let interval = 5min;

  asu-class-pingbot check
  asu-class-pingbot say $owner_id "Listening begun!"

  # Records consecutive errors
  mut consecutive_errors: list = [];
  while true {
    try {
      let state: record = try { open --raw $state_file | from json } | default {}
      let prev_available_classes = $state;
      let user_id = $owner_id

      log debug $"Checking classes for changes in availability: ($class_numbers)"
      
      let classes = $class_numbers 
        | each { class search $in} 
        | flatten 
        | insert seats.prev_available { |class|
          $prev_available_classes | get -o $class.class_number
        } | insert change { |class|
          let seats = $class.seats
          let delta = if $seats.prev_available != null {$seats.available - $seats.prev_available}
          {
            type: (
              if $delta == null {
                "new"
              } else if $delta == 0 {
                "none"
              } else if $seats.available == 0 {
                "close"
              } else if $seats.prev_available == 0 {
                "open"
              } else if $delta > 0 {
                "increase"
              } else if $delta < 0 {
                "decrease"
              }
            ),
            delta: $delta
          }
        }
      # Do not repeatedly notify for the same class
      let changed_classes = $classes 
        | where { |class| $class.change.type != "none" }
      if ($changed_classes | length) > 0 {
        let opened_classes_count = $changed_classes | where { |class| $class.change.type == "open" } | length
        let other_classes_count = ($changed_classes | length) - $opened_classes_count
        let did_a_class_open = $opened_classes_count > 0
        let should_ping = $did_a_class_open

        let title = "Found " + ([
          ...(if $opened_classes_count > 0 {
            let plural_class = if $opened_classes_count == 1 {"class"} else {"classes"}
            [$"($opened_classes_count) opened ($plural_class)"]
          } else {
            []
          }),
          ...(if $other_classes_count > 0 {
            let plural_changes = if $opened_classes_count == 1 {"change"} else {"changes"}
            [$"($other_classes_count) $(if $did_a_class_open {"other"} else {""}) ($plural_changes) in availability"]
          } else {
            []
          })
        ] | str join " and ") + "!"
        log debug $title
        let msg = $title + "\n" + (
          $changed_classes | each { |class|
            let component = match $class.component {
              "LAB" | "REC" => $" ($class.component)",
              _ => ""
            }
            let class_desc = $"($class.class_number) \(($class.subject_number)($component)\)"
            let change_desc = match $class.change.type {
              "new" => "begun being tracked"
              "close" => "closed",
              "open" => "opened",
              "increase" | "decrease" => $"($class.change.type)d by ($class.change.delta)",
              _ => ""
            };
            let change_parentheses = $"\(($class.seats.prev_available | default "null")->($class.seats.available)\)"
            let short_msg = $"($class_desc)'s availability has ($change_desc) ($change_parentheses)!"
            log info $short_msg
            $"($short_msg):
            > ($class.description) runs from ($class.start_time) to ($class.end_time) on ($class.days) at ($class.campus) during session ($class.session)
            > [catalog]\(($class.catalog_link)\)     [add to cart]\(($class.add_to_cart_link)\)
            "
          } | str join "\n"
        );
        asu-class-pingbot say $user_id $msg ...(if $should_ping { [--ping] } else { [] })
      } else {
        log debug "No change found."
      }
      $classes
        | each { |class| [$class.class_number, $class.seats.available] } 
        | into record
        | save $state_file --force
    } catch { |e|
      if $loop {
        # If in loop mode, log the error and continue
        log error $"Error occurred while checking classes: ($e)"
        {error: $e}
      } else {
        # If not in loop mode, forward the error
        error make $e
      }
    } | if (($in | describe -d).type == record and $in.error? != null) {
      let error = $in.error
      $consecutive_errors = $consecutive_errors | append $"($error)"
      if ($consecutive_errors | length) == $max_error_count {
        asu-class-pingbot say --ping $owner_id ($"Many errors encountered!:
        ($consecutive_errors | to nuon --indent 2)" | str substring 0..1996) 
        log critical "Many consecutive errors encountered! Owner pinged!"
      }
    } else {
      $consecutive_errors = [];
    }
    if not $loop {
      break
    }
    sleep $interval # Check every 5 minutes
  }
}

export def "main" [] {
  class_checker_pingbot --loop
}
