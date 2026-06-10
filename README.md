## Notes
- Gets course listings for MAE 201:
  ```nu
  http get --headers {authorization: "Bearer null"} 'https://eadvs-cscc-catalog-api.apps.asu.edu/catalog-microservices/api/v1/search/classes?&refine=Y&catalogNbr=201&subject=MAE&term=2267' | explore
  ```
- Less extensive course data: [data potluck](https://api.myasuplat-dpl.asu.edu/)
  - [Random swagger docs](https://central-openapi-hub.pages.dev/openApi/)
  - Find strm: `https://api.myasuplat-dpl.asu.edu/api/codeset/terms?dateRange=now-20270601`
- Run the cache proxy with Docker Compose:
  ```bash
  cd http-cache; docker compose up
  ```
  