Messages user(s) when availability for a class they're watching has changed.

## Notes
- Usage
  - Discord bot
    1. Place your bot's discord token in `.env`. For example: 
        ```ini
        DISCORD_TOKEN=blah-blah-balh
        ```
    2. Authorize the owner and any users by having them open this link: 
    `https://discord.com/oauth2/authorize?client_id={CLIENT_ID}&integration_type=1&scope=applications.commands` (Replace `{CLIENT_ID}` with the app's client ID)
    3. Add the owner and users with the class numbers they want to watch to `config.json`:
       ```json
       {
         "owner": "owner_user_id",
         "users": {
           "discord_user_id": { "listening_to": ["123456", "111111"] }
         }
       }
       ```
    4. Run `docker compose up -d`
    5. The owner should now be messaged "Listening begun!" by the bot,
        and another message about the classes you're watching.
        If this doesn't occur, either your token or user id is misconfigured.
        Check the logs for error messages by running `docker compose logs`
  - Run the cache proxy thing, if you want (I forgot how it works tbh)
- Todo:
  - Handle new terms
  - Implement slash commands to allow users to configure their own listened classes
  - Reimplement http api in rust? (remove all nushell stuff)
- RE
  - Gets course listings for MAE 201:
    ```nu
    http get --headers {authorization: "Bearer null"} 'https://eadvs-cscc-catalog-api.apps.asu.edu/catalog-microservices/api/v1/search/classes?&refine=Y&catalogNbr=201&subject=MAE&term=2267' | explore
    ```
  - Less extensive course data: [data potluck](https://api.myasuplat-dpl.asu.edu/)
    - [Random swagger docs](https://central-openapi-hub.pages.dev/openApi/)
    - Find strm: `https://api.myasuplat-dpl.asu.edu/api/codeset/terms?dateRange=now-20270601`
  