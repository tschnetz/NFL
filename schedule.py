import pandas as pd
import requests
import streamlit as st
import pytz  # For timezone conversion
from datetime import datetime, timezone

st.set_page_config(layout='wide')


# Set up the API details
url = "https://nfl-api-data.p.rapidapi.com/nfl-events"
querystring = {"year": "2024"}
odds_url = "https://nfl-api-data.p.rapidapi.com/nfl-eventodds"
odds_querystring = {"id":"401249063"}
headers = {
    "x-rapidapi-key": "8f5afa7092mshbb240e4143e782dp18eb0ajsn995280727cd5",
    "x-rapidapi-host": "nfl-api-data.p.rapidapi.com"
}


def get_espn_bet_odds_for_game(game_id):
    querystring = {"id": game_id}
    response = requests.get(odds_url, headers=headers, params=querystring)

    # Load the odds data
    odds_data = response.json()

    # Match the provider ID for ESPN BET (id: "58")
    for item in odds_data.get('items', []):
        if item.get('provider', {}).get('id') == "58":
            return item  # Return the ESPN BET odds

response = requests.get(url, headers=headers, params=querystring)

# Load the JSON response
json_data = response.json()

# Extract the 'leagues' key to get the defined weeks
leagues_data = json_data.get('leagues', [])
if not leagues_data:
    st.write("No leagues data available.")
    st.stop()

# Extract the first league's calendar
nfl_league = leagues_data[0]
calendar_data = nfl_league.get('calendar', [])

# Prepare options for the sidebar: 'Week Label: startDate - endDate'
week_options = []
current_week_index = 0  # To track the current week index for default selection
current_date = datetime.now(timezone.utc)  # Get the current date in UTC

for i, period in enumerate(calendar_data):
    if 'entries' in period:
        for week in period['entries']:
            start_date = datetime.fromisoformat(week['startDate'][:-1]).replace(tzinfo=timezone.utc)
            end_date = datetime.fromisoformat(week['endDate'][:-1]).replace(tzinfo=timezone.utc)
            week_label = f"{week['label']}: {start_date.strftime('%m/%d')} - {end_date.strftime('%m/%d')}"
            week_options.append((week_label, week))

            # Check if the current date is within this week's range
            if start_date <= current_date <= end_date:
                current_week_index = len(week_options) - 1  # Set the index of the current week

# Sidebar for week selection (using only the display labels, default to the current week)
selected_week_label, selected_week_data = st.selectbox(
    "Select a week", week_options, index=current_week_index, format_func=lambda x: x[0]
)

# If the selected week is found, extract the events that belong to this week
if selected_week_data:

    # Get the start and end dates of the selected week
    week_start = datetime.fromisoformat(selected_week_data['startDate'][:-1]).replace(tzinfo=timezone.utc)
    week_end = datetime.fromisoformat(selected_week_data['endDate'][:-1]).replace(tzinfo=timezone.utc)

    # Define the timezone for Eastern Standard Time (EST) / Eastern Daylight Time (EDT)
    eastern = pytz.timezone("America/New_York")

    # Prepare list for selected week games
    selected_week_games = []

    # Extract the 'events' key, which contains detailed game data
    events_data = json_data.get('events', [])

    # Iterate through the events and filter games that are happening within the selected week
    for event in events_data:
        event_start_utc = datetime.fromisoformat(event['date'][:-1]).replace(tzinfo=timezone.utc)

        if week_start <= event_start_utc <= week_end:
            # Convert the event's UTC start time to Eastern Time
            event_start_est = event_start_utc.astimezone(eastern)
            # Format the date in the desired format
            # Extract the network name (assuming it is available in a 'broadcast' or 'network' field)
            # Format the date with the short month and network name
            event_start_est_str = event_start_est.strftime(f'%A, %b %-d @ %-I:%M%p')

            # Extract home and away team information
            home_team = event['competitions'][0]['competitors'][0]['team']
            away_team = event['competitions'][0]['competitors'][1]['team']
            # Get the game ID to query odds
            game_id = event.get('id')
            # Fetch ESPN BET odds for this game
            espn_bet_odds = get_espn_bet_odds_for_game(game_id)
            # Extract scores if available, otherwise display ""
            home_team_score = event['competitions'][0]['competitors'][0].get('score', '')
            away_team_score = event['competitions'][0]['competitors'][1].get('score', '')
            # Extract logos - check if 'logo' key exists and has content
            home_team_logo = home_team.get('logo')
            away_team_logo = away_team.get('logo')
            # Extract venue information (name, city, and state)
            venue = event['competitions'][0]['venue']
            venue_name = venue['fullName']
            venue_city = venue['address']['city']
            venue_state = venue['address'].get('state', '')  # Handle cases where state might not be provided
            # Extract game status, quarter, and clock information
            status = event['status']['type']['name']  # Check if it's 'final' or in-progress
            quarter = event['status'].get('period', 'N/A')  # Period/quarter of the game
            clock = event['status'].get('clock', '')  # Remaining time on the clock
            network_name = event['competitions'][0].get('broadcast', 'N/A')

            # Determine the status to display
            if status == 'STATUS_FINAL':
                game_status = "Final"
            elif status == 'STATUS_SCHEDULED':
                game_status = "Upcoming"
            else:
                game_status = f"{quarter} Qtr., {clock} remaining" if clock else f"Q{quarter}"

            # Extract the relevant game information
            game_info = {
                'Event ID': event.get('id', 'N/A'),
                'Event Name': event.get('name', 'N/A'),
                'Week Label': selected_week_label,
                'Start Date (EST)': event_start_est_str,  # Show the date in the desired format
                'Home Team': home_team['displayName'],
                'Away Team': away_team['displayName'],
                'Home Team Score': home_team_score,  # Display the score if available
                'Away Team Score': away_team_score,  # Display the score if available
                'Home Team Logo': home_team_logo,
                'Away Team Logo': away_team_logo,
                'Venue': venue_name,
                'Location': f"{venue_city}, {venue_state}",  # Show the city and state of the venue
                'Game Status': game_status,
                'Network': network_name,
                'Odds': espn_bet_odds['details'],
            }
            selected_week_games.append(game_info)

    # Create a DataFrame with the games for the selected week
    if selected_week_games:
        games_df = pd.DataFrame(selected_week_games)

        # Display each game's details including logos
        for index, row in games_df.iterrows():

            col1, col2, col3, col4, col5 = st.columns([0.5, 2, 2, 0.5, 2])

            # Display home team logo if available
            with col1:
                if row['Home Team Logo']:
                    st.image(row['Home Team Logo'], width=50)
                else:
                    st.write(f"{row['Home Team']} logo not available.")
            with col2:
                st.write(f"#### {row['Home Team']}")
                st.markdown(f"""<div style='text-align: center'>
                                    <h5><br>{row['Home Team Score']}</h5>
                                </div>
                                """, unsafe_allow_html=True)
            with col3:
                st.markdown(f"""
                                    <div style='text-align: center'>
                                        <h5><br>{row['Game Status']}</h5>
                                        <h6>{row['Odds']}</h6>
                                        <p>{row['Start Date (EST)']}<br>{row['Venue']}<br>{row['Location']}
                                        <br>{row['Network']}
                                        </p>
                                    </div>
                                """, unsafe_allow_html=True)
            with col5:
                st.write(f"#### {row['Away Team']}")
                st.markdown(f"""<div style='text-align: center'>
                                                    <h5><br>{row['Away Team Score']}</h5>
                                                </div>
                                                """, unsafe_allow_html=True)
            with col4:
                if row['Away Team Logo']:
                    st.image(row['Away Team Logo'], width=50)
                else:
                    st.write(f"{row['Away Team']} logo not available.")
    else:
        st.write(f"No games found for {selected_week_label}.")
else:
    st.write("No data found for the selected week.")