import os

import dash
from dash import dcc, html
from dash.dependencies import Input, Output
import json
import requests
import pytz
from datetime import datetime, timezone
import dash_bootstrap_components as dbc
from flask_caching import Cache

# Dash setup
app = dash.Dash(__name__, external_stylesheets=[dbc.themes.BOOTSTRAP])
server = app.server  # Needed if deploying on platforms like Heroku

# Cache config for Flask Caching
cache = Cache(app.server, config={
    'CACHE_TYPE': 'simple',  # or 'filesystem' for larger apps
    'CACHE_DEFAULT_TIMEOUT': 86400  # Cache for 24 hours
})
port = int(os.environ.get('PORT', 8080))
# Constants for API details
API_KEY = "8f5afa7092mshbb240e4143e782dp18eb0ajsn995280727cd5"
NFL_EVENTS_URL = "https://nfl-api-data.p.rapidapi.com/nfl-events"
ODDS_URL = "https://nfl-api-data.p.rapidapi.com/nfl-eventodds"
HEADERS = {
    "x-rapidapi-key": API_KEY,
    "x-rapidapi-host": "nfl-api-data.p.rapidapi.com"
}
# File path for storing last fetched odds
ODDS_FILE_PATH = 'last_fetched_odds.json'

# Interval for updating scores/time every 60 seconds
interval_scores = dcc.Interval(
    id='interval-scores',
    interval=60 * 1000,  # 60 seconds
    n_intervals=0
)

# Interval for updating odds every hour
interval_odds = dcc.Interval(
    id='interval-odds',
    interval=60 * 60 * 1000,  # 1 hour
    n_intervals=0
)


def save_last_fetched_odds():
    """Save the last fetched odds to a JSON file."""
    with open(ODDS_FILE_PATH, 'w') as f:
        json.dump(last_fetched_odds, f)


def load_last_fetched_odds():
    """Load the last fetched odds from a JSON file."""
    try:
        with open(ODDS_FILE_PATH, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        return {}  # Return an empty dictionary if the file doesn't exist


# Function to fetch NFL events data
@cache.memoize(timeout=3600)  # Cache for 1 hour
def fetch_nfl_events():
    print('Fetching NFL Data from API')
    querystring = {"year": "2024"}
    response = requests.get(NFL_EVENTS_URL, headers=HEADERS, params=querystring)

    if response.status_code == 200:
        return response.json()
    else:
        return {}  # Return empty data if API call fails


@cache.memoize(timeout=3600)
def fetch_espn_bet_odds(game_id, game_status):
    """Fetch ESPN BET odds based on game status."""
    if game_status == 'Scheduled':
        print(f"Fetching ESPN BET odds for scheduled game ID: {game_id}")
        querystring = {"id": game_id}
        response = requests.get(ODDS_URL, headers=HEADERS, params=querystring)
        odds_data = response.json()

        for item in odds_data.get('items', []):
            if item.get('provider', {}).get('id') == "58":  # ESPN BET Provider ID
                last_fetched_odds[game_id] = item.get('spread', 'N/A')  # Store the fetched odds
                save_last_fetched_odds()  # Save to file
                return item.get('spread', 'N/A')
    elif game_id not in last_fetched_odds:
        # Odds not available in the dictionary, fetch odds regardless of the game status
        print(f"Fetching ESPN BET odds for game ID: {game_id} as it is not in last fetched odds.")
        querystring = {"id": game_id}
        response = requests.get(ODDS_URL, headers=HEADERS, params=querystring)
        odds_data = response.json()

        for item in odds_data.get('items', []):
            if item.get('provider', {}).get('id') == "58":  # ESPN BET Provider ID
                last_fetched_odds[game_id] = item.get('spread', 'N/A')  # Store the fetched odds
                save_last_fetched_odds()  # Save to file
                return item.get('spread', 'N/A')
    else:
        # Return the last fetched odds if the game is in progress or final
        print(f"Returning last fetched odds for game ID: {game_id}")
        return last_fetched_odds[game_id]  # Return last fetched odds if available

    return None  # Return None if no odds are found


# Function to extract relevant game data
def extract_game_info(event):
    """Extract all relevant game information from an event."""
    eastern = pytz.timezone("America/New_York")
    event_start_utc = datetime.fromisoformat(event['date'][:-1]).replace(tzinfo=timezone.utc)
    event_start_est = event_start_utc.astimezone(eastern)
    event_start_est_str = event_start_est.strftime('%A, %b %-d @ %-I:%M%p')

    home_team = event['competitions'][0]['competitors'][0]['team']
    away_team = event['competitions'][0]['competitors'][1]['team']

    # Get the game status (e.g., Scheduled, In Progress, Final)
    game_status = event['status']['type']['description']

    # Fetch odds based on game status (fetch live odds if scheduled, retain last odds otherwise)
    game_id = event.get('id')
    espn_bet_odds = fetch_espn_bet_odds(game_id, game_status)

    # Extract odds (spread) if available
    odds = espn_bet_odds if isinstance(espn_bet_odds, (float, int)) else 'N/A'  # Handle float correctly

    return {
        'Home Team': home_team['displayName'],
        'Away Team': away_team['displayName'],
        'Home Team Score': event['competitions'][0]['competitors'][0].get('score', 'N/A'),
        'Away Team Score': event['competitions'][0]['competitors'][1].get('score', 'N/A'),
        'Odds': odds,
        'Home Team Logo': home_team.get('logo'),
        'Away Team Logo': away_team.get('logo'),
        'Home Team Color': f"#{home_team.get('color', '000000')}",
        'Away Team Color': f"#{away_team.get('color', '000000')}",
        'Venue': event['competitions'][0]['venue']['fullName'],
        'Location': f"{event['competitions'][0]['venue']['address']['city']}",
        'Network': event['competitions'][0].get('broadcast', 'N/A'),  # Include the broadcast network
        'Game Status': game_status,
        'Start Date (EST)': event_start_est_str,
        'Quarter': event.get('status', {}).get('period', None),
        'Time Remaining': event.get('status', {}).get('displayClock', None),
    }


# Check to see if last_fetched_odds.json exists
if os.path.exists(ODDS_FILE_PATH):
    last_fetched_odds = load_last_fetched_odds()
else:
    last_fetched_odds = {}

# Dash layout setup
app.layout = dbc.Container([
    interval_scores,  # Add scores interval
    interval_odds,    # Add odds interval
    dbc.Row(dbc.Col(html.H1("NFL Real-Time Game Updates"), className="text-center")),
    dcc.Store(id='selected-week', data={'value': None}),  # Store selected week in dcc.Store
    dbc.Row(dbc.Col(dcc.Dropdown(id='week-selector', options=[], placeholder="Select a week"))),
    dbc.Row(
        dbc.Col(
            dcc.Loading(  # Add loading spinner here
                id='loading',
                type='circle',  # Choose spinner type (circle, default, or graph)
                children=[html.Div(id='game-info')]  # This is the div where game info will be displayed
            )
        )
    )
])

@app.callback(
    [Output('week-selector', 'options'), Output('week-selector', 'value')],
    [Input('interval-scores', 'n_intervals')]
)
def update_week_options(n_intervals):
    data = fetch_nfl_events()
    leagues_data = data.get('leagues', [])

    week_options = []
    selected_value = None
    current_date = datetime.now(timezone.utc)

    if leagues_data:
        nfl_league = leagues_data[0]
        calendar_data = nfl_league.get('calendar', [])

        week_counter = 0

        for i, period in enumerate(calendar_data):
            if 'entries' in period:
                for week in period['entries']:
                    start_date = datetime.fromisoformat(week['startDate'][:-1]).replace(tzinfo=timezone.utc)
                    end_date = datetime.fromisoformat(week['endDate'][:-1]).replace(tzinfo=timezone.utc)
                    week_label = f"{week['label']}: {start_date.strftime('%m/%d')} - {end_date.strftime('%m/%d')}"

                    week_options.append({'label': week_label, 'value': week_counter})

                    if start_date <= current_date <= end_date:
                        selected_value = week_counter

                    week_counter += 1  # Increment the counter to ensure each value is unique

    if selected_value is None and week_options:
        selected_value = week_options[0]['value']

    return week_options, selected_value


@app.callback(
    Output('selected-week', 'data'),  # Store selected week in dcc.Store
    [Input('week-selector', 'value')]
)
def store_selected_week(selected_week):
    return {'value': selected_week}  # Store the selected week


@app.callback(
    Output('game-info', 'children'),
    [Input('selected-week', 'data'),
     Input('interval-scores', 'n_intervals'),
     Input('interval-odds', 'n_intervals')]
)
def display_game_info(stored_week_data, score_intervals, odds_intervals):
    selected_week_index = stored_week_data['value']  # Access the stored week
    data = fetch_nfl_events()
    leagues_data = data.get('leagues', [])

    if not leagues_data:
        return html.P("No leagues data available.")

    nfl_league = leagues_data[0]
    calendar_data = nfl_league.get('calendar', [])

    if selected_week_index is None:
        return html.P("Invalid week selection.")

    week_data = None  # This variable holds the found week data
    week_counter = 0

    for period in calendar_data:
        if 'entries' in period:
            for week in period['entries']:
                if week_counter == selected_week_index:
                    week_data = week  # Assign found week to week_data
                    break
                week_counter += 1

        if week_data:
            break

    if not week_data:
        return html.P("Selected week data not found.")
    else:
        print(f"Selected week data: {week_data}")

    week_start = datetime.fromisoformat(week_data['startDate'][:-1]).replace(tzinfo=timezone.utc)
    week_end = datetime.fromisoformat(week_data['endDate'][:-1]).replace(tzinfo=timezone.utc)

    events_data = data.get('events', [])
    selected_week_games = [
        event for event in events_data
        if week_start <= datetime.fromisoformat(event['date'][:-1]).replace(tzinfo=timezone.utc) <= week_end
    ]

    print(f"Filtered games: {len(selected_week_games)} games found for the week")

    games_info = []
    for game in selected_week_games:
        # Extract game information, including updating odds
        game_info = extract_game_info(game)

        games_info.append(
            dbc.Row([
                dbc.Col(
                    html.Img(src=game_info['Home Team Logo'], height="50px"),
                    width=1, style={'text-align': 'center'}
                ),
                dbc.Col(
                    html.Div([
                        html.H4(game_info['Home Team'], style={'color': game_info['Home Team Color']}),
                        # Only show the score if the game is not scheduled
                        html.H4(f"{game_info['Home Team Score']}" if game_info['Game Status'] != 'Scheduled' else "")
                    ], style={'text-align': 'center'}),
                    width=3
                ),
                dbc.Col(
                    html.Div([
                        html.H5(game_info['Game Status']),
                        # Check if the game is not Final before displaying quarter/time
                        (html.H6(f"{game_info['Quarter']} Qtr, {game_info['Time Remaining']} remaining")
                        if game_info['Game Status'] != 'Final' and game_info['Quarter'] else ""),
                        html.H6(game_info['Odds']) if game_info['Odds'] else "",
                        html.P(game_info['Start Date (EST)'], style={'margin': '0', 'padding': '0'}),
                        html.P(game_info['Venue'], style={'margin': '0', 'padding': '0'}),
                        html.P(game_info['Location'], style={'margin': '0', 'padding': '0'}),
                        html.P(game_info['Network'], style={'margin': '0', 'padding': '0'})
                    ], style={'text-align': 'center'}),
                    width=4
                ),
                dbc.Col(
                    html.Div([
                        html.H4(game_info['Away Team'], style={'color': game_info['Away Team Color']}),
                        # Only show the score if the game is not scheduled
                        html.H4(f"{game_info['Away Team Score']}" if game_info['Game Status'] != 'Scheduled' else "")
                    ], style={'text-align': 'center'}),
                    width=3
                ),
                dbc.Col(
                    html.Img(src=game_info['Away Team Logo'], height="50px"),
                    width=1, style={'text-align': 'center'}
                )
            ], className="game-row", style={'padding': '10px'})
        )

        games_info.append(html.Hr())

    return games_info


if __name__ == "__main__":
    app.run_server(debug=True, port=port)