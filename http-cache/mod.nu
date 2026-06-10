export def --env start [] {
  mkdir .cache
  touch .cache/cached-flows.mitm
  job spawn { cd http-cache; docker compose up }
  $env.http_proxy  = "http://localhost:8080"
  $env.https_proxy = "http://localhost:8080"
  $env.http_cache_active = true
}
export def stop [] {
  do { cd http-cache; docker compose down }
  export-env {
    $env.http_proxy  = ""
    $env.https_proxy = ""
    $env.http_cache_active = false
  }
}
export def clear [] {
  if $env.http_cache_active != true {
    return "Cache is not active. Run 'start' first."
  }
  rm -rf .cache/cached-flows.mitm
  touch .cache/cached-flows.mitm
  do { cd http-cache; docker compose restart }
}