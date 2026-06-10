use std::path::PathBuf;

use clap::{Parser, Subcommand};

use dotenvy::dotenv_iter;
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
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Runs slash command listener
    Serve {
        /// lists test values
        #[arg(short, long)]
        list: bool,
    },
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

    // Create a new instance of the Client, logging in as a bot.
    let mut client = Client::builder(&token, intents)
        .event_handler(Handler)
        .await
        .expect("Err creating client");

    match cli.command {
        Commands::Serve { list } => {
            // Start listening for events by starting a single shard
            if let Err(why) = client.start().await {
                println!("Client error: {why:?}");
            };
        }
        Commands::Say { user_id, content } => {
            client
                .http
                .get_user(user_id.into())
                .await
                .expect("User should exist and be accessible")
                .create_dm_channel(&client.http)
                .await
                .expect("Retrieving DM channel should succeed")
                .say(&client.http, content)
                .await
                .expect("Message should send successfully");
        }
    }

    Ok(())
}
