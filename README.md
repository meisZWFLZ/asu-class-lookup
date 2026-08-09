Messages user(s) when availability for a class they're watching has changed.

## Notes
- Usage
  - Discord bot
    1. Place your bot's discord token in `.env`. For example:      
      ```ini
      DISCORD_TOKEN=blah-blah-balh
      ```
    2. Set your user id and the class numbers you want to watch in `asu.nu`
    3. Run `docker compose up -d`
    4. You should now be messaged "Listening begun!" by the bot, 
        and another message about the classes you're watching.
        If this doesn't occur, either your token or user id is misconfigured.
        Check the logs for error messages by running `docker compose logs`
  - Run the cache proxy thing, if you want (I forgot how it works tbh)
- Todo:
  - Don't hardcode user and watched class numbers
  - Handle new terms
  - Implement slash commands
  - Reimplement http api in rust? (remove all nushell stuff)
- RE
  - Gets course listings for MAE 201:
    ```nu
    http get --headers {authorization: "Bearer null"} 'https://eadvs-cscc-catalog-api.apps.asu.edu/catalog-microservices/api/v1/search/classes?&refine=Y&catalogNbr=201&subject=MAE&term=2267' | explore
    ```
  - Less extensive course data: [data potluck](https://api.myasuplat-dpl.asu.edu/)
    - [Random swagger docs](https://central-openapi-hub.pages.dev/openApi/)
    - Find strm: `https://api.myasuplat-dpl.asu.edu/api/codeset/terms?dateRange=now-20270601`
  