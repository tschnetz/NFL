import pandas as pd
import requests
import streamlit as st
import pytz  # For timezone conversion
from datetime import datetime, timezone
from streamlit_autorefresh import st_autorefresh

st.set_page_config(layout='wide')

# Constants for API details
API_KEY = "8f5afa7092mshbb240e4143e782dp18eb0ajsn995280727cd5"
NFL_EVENTS_URL = "https://nfl-api-data.p.rapidapi.com/nfl-events"
ODDS_URL = "https://nfl-api-data.p.rapidapi.com/nfl-eventodds"
HEADERS = {
    "x-rapidapi-key": API_KEY,
    "x-rapidapi-host": "nfl-api-data.p.rapidapi.com"
}


# Cache the NFL events data (static for 24 hours)
@st.cache_data(ttl=86400)  # Cache for 24 hours (86400 seconds)
def fetch_nfl_events(querystring):
    """Fetch NFL events data from the API (cached)."""
    response = requests.get(NFL_EVENTS_URL, headers=HEADERS, params=querystring)
    return response.json()


# Cache the ESPN BET odds (refresh every hour)
@st.cache_data(ttl=3600)  # Cache for 1 hour (3600 seconds)
def fetch_espn_bet_odds(game_id):
    """Fetch ESPN BET odds for a specific game (cached for 1 hour)."""
    querystring = {"id": game_id}
    response = requests.get(ODDS_URL, headers=HEADERS, params=querystring)
    odds_data = response.json()
    for item in odds_data.get('items', []):
        if item.get('provider', {}).get('id') == "58":  # ESPN BET Provider ID
            return item  # Return ESPN BET odds if found
    return None


# Fetch real-time score and time from ESPN API
def get_score_time(game_id):
    """Fetch real-time score, quarter, and time remaining using ESPN's Unofficial API."""
    url = "https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard"
    response = requests.get(url)
    data = response.json()

    for event in data['events']:
        if event['id'] == game_id:  # Match the game by ID
            status = event['status']['type']['description']  # Game status (e.g., "In Progress", "Final", etc.)
            home_team = event['competitions'][0]['competitors'][0]['team']['displayName']
            away_team = event['competitions'][0]['competitors'][1]['team']['displayName']
            home_score = event['competitions'][0]['competitors'][0].get('score', 'N/A')
            away_score = event['competitions'][0]['competitors'][1].get('score', 'N/A')

            # Get quarter and time remaining (only if the game is in progress)
            if event['status']['type']['id'] == "2":  # Status ID 2 means the game is in progress
                quarter = event['status'].get('period', 'N/A')  # The current quarter (period)
                time_remaining = event['status'].get('displayClock', 'N/A')  # Time remaining in the current quarter
            else:
                quarter = None  # Don't display if not in progress
                time_remaining = None  # Don't display if not in progress

            return home_score, away_score, status, quarter, time_remaining

    return None, None, "N/A", None, None  # Default if the game is not found or no data available


def fetch_rapid_api_closing_odds(game_id):
    """Fetch closing odds for a specific game from the Rapid API."""
    querystring = {"id": game_id}
    response = requests.get(ODDS_URL, headers=HEADERS, params=querystring)
    odds_data = response.json()

    # Extract closing odds (if available)
    for item in odds_data.get('items', []):
        if item.get('provider', {}).get('name') == "Closing Odds":
            return item['details']  # Return the closing odds details

    return "Odds not available"


# Fetch past scores from Rapid API
def get_past_scores(event):
    """Fetch past scores and closing odds for past weeks from the Rapid API."""
    home_team_score = event['competitions'][0]['competitors'][0].get('score', '')
    away_team_score = event['competitions'][0]['competitors'][1].get('score', '')
    status = event['status']['type']['description']

    # Fetch odds (closing odds for past games) if available from Rapid API
    game_id = event.get('id')
    closing_odds = fetch_rapid_api_closing_odds(game_id)

    return home_team_score, away_team_score, status, closing_odds


def extract_game_info(event, week_label, use_rapid_api=False):
    """Extract all relevant game information from an event."""
    eastern = pytz.timezone("America/New_York")

    # Convert UTC event start time to Eastern Time
    event_start_utc = datetime.fromisoformat(event['date'][:-1]).replace(tzinfo=timezone.utc)
    event_start_est = event_start_utc.astimezone(eastern)
    event_start_est_str = event_start_est.strftime('%A, %b %-d @ %-I:%M%p')

    # Extract team information
    home_team = event['competitions'][0]['competitors'][0]['team']
    away_team = event['competitions'][0]['competitors'][1]['team']

    # Fetch scores and odds based on whether we're using the Rapid API or ESPN API
    if use_rapid_api:
        # Use Rapid API for past games, including closing odds
        home_score, away_score, status, closing_odds = get_past_scores(event)
        quarter, time_remaining = None, None  # No need for quarter and time remaining in past games
        odds_details = closing_odds  # Show closing odds for past games
    else:
        # Use ESPN API for real-time data, including odds for current/future games
        game_id = event.get('id')
        home_score, away_score, status, quarter, time_remaining = get_score_time(game_id)

        # If status is empty, assume the game is scheduled (future games)
        if status in [None, '', 'N/A']:
            status = "Scheduled"

        # Fetch odds from ESPN API
        odds_details = "Odds N/A"  # Default to "Odds N/A" if not available
        espn_bet_odds = fetch_espn_bet_odds(game_id)
        if espn_bet_odds:
            odds_details = espn_bet_odds['details']

    # Extract venue information
    venue = event['competitions'][0]['venue']
    venue_name = venue['fullName']
    venue_city = venue['address']['city']
    venue_state = venue['address'].get('state', '')

    # Team colors (use default if not available)
    home_team_color = f"#{home_team.get('color', '000000')}"  # Default to black
    away_team_color = f"#{away_team.get('color', '000000')}"  # Default to black

    # Return the extracted information as a dictionary
    return {
        'Event ID': event.get('id', 'N/A'),  # Handle missing event ID for past games
        'Event Name': event.get('name', 'N/A'),
        'Week Label': week_label,
        'Start Date (EST)': event_start_est_str,
        'Home Team': home_team['displayName'],
        'Away Team': away_team['displayName'],
        'Home Team Score': home_score,
        'Away Team Score': away_score,
        'Quarter': quarter,  # Only display if in progress
        'Time Remaining': time_remaining,  # Only display if in progress
        'Game Status': status,  # Use "Scheduled" for future games, "Final" for past games
        'Home Team Logo': home_team.get('logo'),
        'Away Team Logo': away_team.get('logo'),
        'Home Team Color': home_team_color,
        'Away Team Color': away_team_color,
        'Venue': venue_name,
        'Location': f"{venue_city}, {venue_state}",
        'Network': event['competitions'][0].get('broadcast', 'N/A'),
        'Odds': odds_details,  # Show closing odds for past games, ESPN odds for current/future games
    }


def display_game_info(games_df):
    """Display the game information in a Streamlit dashboard."""
    for index, row in games_df.iterrows():
        col1, col2, col3, col4, col5 = st.columns([0.5, 2, 2, 0.5, 2])

        with col1:
            if row['Home Team Logo']:
                st.image(row['Home Team Logo'], width=50)
            else:
                st.write(f"{row['Home Team']} logo not available.")

        with col2:
            st.markdown(
                f"""<div style='text-align: center;'>
                        <h4 style='color:{row['Home Team Color']}'>{row['Home Team']}</h4>
                        <h4>{row['Home Team Score']}</h4>
                    </div>""", unsafe_allow_html=True
            )

        with col3:
            game_status_info = f"<br><h5>{row['Game Status']}</h5>"

            # Only display quarter and time remaining if the game is in progress
            if row['Quarter'] and row['Time Remaining']:
                game_status_info += f"<h6>{row['Quarter']} Qtr, {row['Time Remaining']} remaining</h6>"

            game_status_info += f"<h6>{row['Odds']}</h6>"
            game_status_info += f"<p>{row['Start Date (EST)']}<br>{row['Venue']}<br>{row['Location']}<br>{row['Network']}</p>"

            st.markdown(f"<div style='text-align: center'>{game_status_info}</div>", unsafe_allow_html=True)

        with col5:
            st.markdown(
                f"""<div style='text-align: center;'>
                        <h4 style='color:{row['Away Team Color']}; margin: 0;'>{row['Away Team']}</h4>
                        <h4>{row['Away Team Score']}</h4>
                    </div>""", unsafe_allow_html=True
            )

        with col4:
            if row['Away Team Logo']:
                st.image(row['Away Team Logo'], width=50)
            else:
                st.write(f"{row['Away Team']} logo not available.")
        st.markdown(f"<hr>", unsafe_allow_html=True)


# Cache the selected week's data to avoid re-fetching from Rapid API
@st.cache_data(ttl=None, show_spinner=False)
def get_cached_week_data(selected_week_data, selected_week_label):
    """Cache the Rapid API data for the selected week."""
    week_start = datetime.fromisoformat(selected_week_data['startDate'][:-1]).replace(tzinfo=timezone.utc)
    week_end = datetime.fromisoformat(selected_week_data['endDate'][:-1]).replace(tzinfo=timezone.utc)
    querystring = {"year": "2024"}

    json_data = fetch_nfl_events(querystring)
    events_data = json_data.get('events', [])

    selected_week_games = [
        extract_game_info(event, selected_week_label, use_rapid_api=True)
        for event in events_data
        if week_start <= datetime.fromisoformat(event['date'][:-1]).replace(tzinfo=timezone.utc) <= week_end
    ]

    return pd.DataFrame(selected_week_games)


def main():
    """Main function to drive the Streamlit app."""
    # Automatically refresh every 30 seconds for ESPN data
    count = st_autorefresh(interval=30000, limit=None, key="mycounter")

    # Query for static NFL events data (using caching)
    querystring = {"year": "2024"}
    json_data = fetch_nfl_events(querystring)

    # Extract weeks and prepare sidebar selection
    leagues_data = json_data.get('leagues', [])
    if not leagues_data:
        st.write("No leagues data available.")
        st.stop()

    nfl_league = leagues_data[0]
    calendar_data = nfl_league.get('calendar', [])

    week_options = []
    current_week_index = 0
    current_date = datetime.now(timezone.utc)

    for i, period in enumerate(calendar_data):
        if 'entries' in period:
            for week in period['entries']:
                start_date = datetime.fromisoformat(week['startDate'][:-1]).replace(tzinfo=timezone.utc)
                end_date = datetime.fromisoformat(week['endDate'][:-1]).replace(tzinfo=timezone.utc)
                week_label = f"{week['label']}: {start_date.strftime('%m/%d')} - {end_date.strftime('%m/%d')}"
                week_options.append((week_label, week))

                if start_date <= current_date <= end_date:
                    current_week_index = len(week_options) - 1

    selected_week_label, selected_week_data = st.selectbox(
        "Select a week", week_options, index=current_week_index, format_func=lambda x: x[0]
    )

    if selected_week_data:
        week_start = datetime.fromisoformat(selected_week_data['startDate'][:-1]).replace(tzinfo=timezone.utc)
        week_end = datetime.fromisoformat(selected_week_data['endDate'][:-1]).replace(tzinfo=timezone.utc)

        use_rapid_api = week_end < current_date  # Use Rapid API if week has passed

        if use_rapid_api:
            # Fetch static data from Rapid API for past weeks
            games_df = get_cached_week_data(selected_week_data, selected_week_label)
        else:
            # Fetch real-time data for current/future weeks using ESPN API
            events_data = json_data.get('events', [])
            selected_week_games = [
                extract_game_info(event, selected_week_label, use_rapid_api=False)
                for event in events_data
                if week_start <= datetime.fromisoformat(event['date'][:-1]).replace(tzinfo=timezone.utc) <= week_end
            ]
            games_df = pd.DataFrame(selected_week_games)

        # Display game information
        if not games_df.empty:
            display_game_info(games_df)
        else:
            st.write(f"No games found for {selected_week_label}.")
    else:
        st.write("No data found for the selected week.")


if __name__ == "__main__":
    main()