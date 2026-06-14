use std::path::PathBuf;

use clap::{Parser, Subcommand};

use serenity::async_trait;
use serenity::model::channel::Message;
use serenity::prelude::*;

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Token for the bot to use
    #[arg(short, long, env = "DISCORD_TOKEN")]
    token: Option<String>,

    /// Sets a custom env file
    #[arg(short, long, value_name = "FILE")]
    env: Option<PathBuf>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Runs slash command listener
    /// TODO: Implement slash command listener
    Serve,
    /// Sends a message to the specified user
    Say {
        /// The user ID to send the message to
        user_id: u64,
        /// The message content to send
        content: String,
    },
}
struct Handler;

#[async_trait]
impl EventHandler for Handler {
    async fn message(&self, ctx: Context, msg: Message) {
        if msg.content == "!ping" {
            if let Err(why) = msg.channel_id.say(&ctx.http, "Pong!").await {
                println!("Error sending message: {why:?}");
            }
        }
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    let token = cli
        .token
        .or_else(|| {
            dotenvy::from_filename(cli.env.unwrap_or_else(|| PathBuf::from(".env")))
                .ok()
                .and_then(|_| {
                    dotenvy::vars()
                        .find(|(key, _)| key == "DISCORD_TOKEN")
                        .map(|(_, value)| value)
                })
        })
        .expect("Token must exist in cli option, environmnet variable, or .env file.");

    // Set gateway intents, which decides what events the bot will be notified about
    let intents = GatewayIntents::GUILD_MESSAGES
        | GatewayIntents::DIRECT_MESSAGES
        | GatewayIntents::MESSAGE_CONTENT;

    match cli.command {
        Command::Serve => {
            // Create a new instance of the Client, logging in as a bot.
            let mut client = Client::builder(&token, intents)
                .event_handler(Handler)
                .await?;
            // Start listening for events by starting a single shard
            if let Err(why) = client.start().await {
                println!("Client error: {why:?}");
            };
        }
        Command::Say { user_id, content } => {
            let client = Client::builder(&token, intents).await?;
            client
                .http
                .get_user(user_id.into())
                .await?
                .create_dm_channel(&client.http)
                .await?
                .say(&client.http, content)
                .await?;
        }
    }

    Ok(())
}
