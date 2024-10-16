import dash
from dash import dcc, html
import dash_bootstrap_components as dbc
from dash.dependencies import Input, Output, State
from datetime import datetime, timezone
from dotenv import load_dotenv
from flask_caching import Cache
import json
import os
import requests
import pytz


load_dotenv()

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
API_KEY = os.getenv("API_KEY")
NFL_EVENTS_URL = "https://nfl-api-data.p.rapidapi.com/nfl-events"
ODDS_URL = "https://nfl-api-data.p.rapidapi.com/nfl-eventodds"
SCORINGPLAYS_URL = "https://nfl-api-data.p.rapidapi.com/nfl-scoringplays"
SCOREBOARD_URL = "https://nfl-api-data.p.rapidapi.com/nfl-single-events"
HEADERS = {
    "x-rapidapi-key": API_KEY,
    "x-rapidapi-host": "nfl-api-data.p.rapidapi.com"
}
# File path for storing last fetched odds
ODDS_FILE_PATH = 'last_fetched_odds.json'

# Interval for updating scores/time every 60 seconds
INTERVAL_SCORES = dcc.Interval(
    id='interval-scores',
    interval=60 * 1000,  # 60 seconds
    n_intervals=0
)

# Interval for updating odds every hour
INTERVAL_ODDS = dcc.Interval(
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
@cache.memoize(timeout=60)
def fetch_nfl_events():
    # print('Fetching NFL Data from API')
    querystring = {"year": "2024"}
    response = requests.get(NFL_EVENTS_URL, headers=HEADERS, params=querystring)

    if response.status_code == 200:
        return response.json()
    else:
        return {}  # Return empty data if API call fails


@cache.memoize(timeout=60)
def fetch_game_scoreboard(game_id):
    # print('Fetching NFL Data from API')
    querystring = {"id":game_id}
    response = requests.get(SCOREBOARD_URL, headers=HEADERS, params=querystring)

    if response.status_code == 200:
        return response.json()
    else:
        return {}  # Return empty data if API call fails


@cache.memoize(timeout=3600)
def fetch_espn_bet_odds(game_id, game_status):
    """Fetch ESPN BET odds based on game status."""
    if game_status == 'Scheduled':
        # print(f"Fetching ESPN BET odds for scheduled game ID: {game_id}")
        querystring = {"id": game_id}
        response = requests.get(ODDS_URL, headers=HEADERS, params=querystring)
        odds_data = response.json()

        for item in odds_data.get('items', []):
            if item.get('provider', {}).get('id') == "58":  # ESPN BET Provider ID
                last_fetched_odds[game_id] = item.get('details', 'N/A')  # Store the fetched odds
                save_last_fetched_odds()  # Save to file
                return item.get('details', 'N/A')
    elif game_id not in last_fetched_odds:
        # Odds not available in the dictionary, fetch odds regardless of the game status
        # print(f"Fetching ESPN BET odds for game ID: {game_id} as it is not in last fetched odds.")
        querystring = {"id": game_id}
        response = requests.get(ODDS_URL, headers=HEADERS, params=querystring)
        odds_data = response.json()

        for item in odds_data.get('items', []):
            if item.get('provider', {}).get('id') == "58":  # ESPN BET Provider ID
                last_fetched_odds[game_id] = item.get('details', 'N/A')  # Store the fetched odds
                save_last_fetched_odds()  # Save to file
                return item.get('details', 'N/A')
    else:
        # Return the last fetched odds if the game is in progress or final
        # print(f"Returning last fetched odds for game ID: {game_id}")
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
    odds = fetch_espn_bet_odds(game_id, game_status)

    # Extract overall records from the statistics
    home_team_record = event['competitions'][0]['competitors'][0]['records'][0]['summary']
    away_team_record = event['competitions'][0]['competitors'][1]['records'][0]['summary']

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
        'Home Team Record': home_team_record,  # Added home team record
        'Away Team Record': away_team_record  # Added away team record
    }


@app.callback(
    Output('week-selector', 'options'),
    Output('week-options-store', 'data'),
    Output('week-selector', 'value'),
    Output('nfl-events-data', 'data'),  # Store NFL events data here
    [Input('week-options-store', 'data')]
)
def update_week_options(week_options_fetched):
    week_options = []  # Initialize week_options here

    if week_options_fetched or week_options:  # Check if already fetched or if week_options is not empty
        raise dash.exceptions.PreventUpdate

    # Fetch NFL events once and store them
    data = fetch_nfl_events()
    leagues_data = data.get('leagues', [])

    if not leagues_data:
        return [], False, None, {}

    nfl_league = leagues_data[0]
    calendar_data = nfl_league.get('calendar', [])
    week_options = []
    selected_value = None
    current_date = datetime.now(timezone.utc)

    week_counter = 0
    for period in calendar_data:
        if 'entries' in period:
            for week in period['entries']:
                start_date = datetime.fromisoformat(week['startDate'][:-1]).replace(tzinfo=timezone.utc)
                end_date = datetime.fromisoformat(week['endDate'][:-1]).replace(tzinfo=timezone.utc)
                week_label = f"{week['label']}: {start_date.strftime('%m/%d')} - {end_date.strftime('%m/%d')}"

                week_options.append({'label': week_label, 'value': week_counter})

                if start_date <= current_date <= end_date:
                    selected_value = week_counter

                week_counter += 1

    if selected_value is None and week_options:
        selected_value = week_options[0]['value']

    return week_options, True, selected_value, data  # Return the fetched data to store it


@app.callback(
    Output('selected-week', 'data'),
    [Input('week-options-store', 'data')]
)
def store_selected_week(week_options_fetched):
    if not week_options_fetched:
        raise dash.exceptions.PreventUpdate

    # print("Initial store_selected_week")
    data = fetch_nfl_events()  # You might not need to fetch the data again here
    leagues_data = data.get('leagues', [])

    selected_value = None  # Initialize selected_value
    if leagues_data:
        nfl_league = leagues_data[0]
        calendar_data = nfl_league.get('calendar', [])
        current_date = datetime.now(timezone.utc)

        week_counter = 0
        for i, period in enumerate(calendar_data):
            if 'entries' in period:
                for week in period['entries']:
                    start_date = datetime.fromisoformat(week['startDate'][:-1]).replace(tzinfo=timezone.utc)
                    end_date = datetime.fromisoformat(week['endDate'][:-1]).replace(tzinfo=timezone.utc)

                    if start_date <= current_date <= end_date:
                        selected_value = week_counter
                        break  # Exit the loop once the current week is found

                    week_counter += 1

    # Now you have the selected_value
    # print("Selected Value:", selected_value)
    return {'value': selected_value}


@app.callback(
    Output('game-info', 'children'),
    Output('in-progress-flag', 'data'),
    [Input('week-selector', 'value'),
     Input('scores-data', 'data')],
    [State('nfl-events-data', 'data')],  # Use NFL events data from Store
    prevent_initial_call=True
)
def display_game_info(selected_week_index, scores_data, nfl_events_data):
    ctx = dash.callback_context
    triggered_by_week_selection = any(
        'week-selector' in trigger['prop_id'] for trigger in ctx.triggered
    )

    if not triggered_by_week_selection and (not scores_data or not any(scores_data)):
        raise dash.exceptions.PreventUpdate  # Prevent update if not triggered by week selection or if scores_data is empty

    data = nfl_events_data  # Use cached data from dcc.Store
    leagues_data = data.get('leagues', [])

    if not leagues_data:
        return html.P("No leagues data available."), False  # Return False for games_in_progress

    nfl_league = leagues_data[0]
    calendar_data = nfl_league.get('calendar', [])

    if selected_week_index is None:
        return html.P("Invalid week selection."), False  # Return False for games_in_progress

    week_data = None
    week_counter = 0

    # Find the selected week data
    for period in calendar_data:
        if 'entries' in period:
            for week in period['entries']:
                if week_counter == selected_week_index:
                    week_data = week
                    break
                week_counter += 1

        if week_data:
            break

    if not week_data:
        return html.P("Selected week data not found."), False  # Return False for games_in_progress

    week_start = datetime.fromisoformat(week_data['startDate'][:-1]).replace(tzinfo=timezone.utc)
    week_end = datetime.fromisoformat(week_data['endDate'][:-1]).replace(tzinfo=timezone.utc)

    events_data = data.get('events', [])
    selected_week_games = [
        event for event in events_data
        if week_start <= datetime.fromisoformat(event['date'][:-1]).replace(tzinfo=timezone.utc) <= week_end
    ]

    games_in_progress = any(game['status']['type']['description'] == 'In Progress' for game in selected_week_games)

    # Sort the games based on their status
    sorted_games = sorted(selected_week_games, key=lambda x: (
        x['status']['type']['description'] == 'Final',  # Place Final last
        x['status']['type']['description'] == 'Scheduled',  # Place Scheduled next
    ))

    games_info = []
    for game in sorted_games:
        game_info = extract_game_info(game)
        game_id = game.get('id')
        home_color = game_info['Home Team Color']
        away_color = game_info['Away Team Color']

        # Update scores from scores_data, including possession info
        possession_team = None
        if scores_data:
            for score_data in scores_data:
                if score_data.get('game_id') == game_id:
                    game_info['Home Team Score'] = score_data.get('Home Team Score', 'N/A')
                    game_info['Away Team Score'] = score_data.get('Away Team Score', 'N/A')
                    down_distance = score_data.get('Down Distance', '')  # Add down distance
                    possession_team = score_data.get('Possession', 'N/A')  # Get possession team
                    break

        # Conditionally add the football emoji and down distance for the team with possession
        home_team_score_display = [html.H4(game_info['Home Team Score'])]
        away_team_score_display = [html.H4(game_info['Away Team Score'])]
        home_team_extra_info = []
        away_team_extra_info = []

        if possession_team == game_info['Home Team']:
            home_team_score_display.append(" 🏈")  # Football emoji next to home team score
            home_team_extra_info.append(html.Br())  # Add blank line
            home_team_extra_info.append(html.H6(down_distance))  # Add down distance info

        elif possession_team == game_info['Away Team']:
            away_team_score_display.append(" 🏈")  # Football emoji next to away team score
            away_team_extra_info.append(html.Br())  # Add blank line
            away_team_extra_info.append(html.H6(down_distance))  # Add down distance info

        games_info.append(
            dbc.Button(
                dbc.Row([
                    dbc.Col(html.Img(src=game_info['Home Team Logo'], height="60px"), width=1,
                            style={'text-align': 'center'}),
                    dbc.Col(
                        html.Div([
                            html.H4(game_info['Home Team'], style={'color': game_info['Home Team Color']}),
                            html.P(f"{game_info['Home Team Record']}", style={'margin': '0', 'padding': '0'}),
                            html.Div(home_team_score_display), # Display home team score + 🏈 if possession
                            html.P(home_team_extra_info)  # Down distance for home team if possession
                        ], style={'text-align': 'center'}),
                        width=3
                    ),
                    dbc.Col(
                        html.Div([
                            html.H5(game_info['Game Status']),
                            (html.H6(f"{game_info['Quarter']} Qtr, {game_info['Time Remaining']} remaining")
                             if game_info['Game Status'] == 'In Progress' else ""),
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
                            html.P(f"{game_info['Away Team Record']}", style={'margin': '0', 'padding': '0'}),
                            html.Div(away_team_score_display),  # Display away team score + 🏈 if possession
                            html.P(away_team_extra_info)  # Down distance for away team if possession
                        ], style={'text-align': 'center'}),
                        width=3
                    ),
                    dbc.Col(html.Img(src=game_info['Away Team Logo'], height="60px"), width=1,
                            style={'text-align': 'center'}),
                ], className="game-row", style={'padding': '10px'}),
                id={'type': 'game-button', 'index': game_id},  # Unique ID for each game button
                n_clicks=0,
                color='light',
                className='dash-bootstrap',
                style={
                    '--team-home-color': home_color,  # Pass team home color
                    '--team-away-color': away_color,  # Pass team away color
                    'width': '100%',
                    'text-align': 'left'
                },
                value=game_id,  # Pass the game_id as the button's value
            )
        )
        games_info.append(html.Div(id={'type': 'scoring-plays', 'index': game_id}, children=[]))
        games_info.append(html.Hr())

    return games_info, games_in_progress


@app.callback(
    Output('scores-data', 'data'),  # Output to dcc.Store's data property
    Output('in-progress-flag', 'data', allow_duplicate=True),  # Output for in-progress flag
    [Input('interval-scores', 'n_intervals')],
    [State('scores-data', 'data'),  # Access data from dcc.Store
     State('nfl-events-data', 'data')],  # Use the events data stored earlier
    prevent_initial_call=True
)
def update_scores(n_intervals, prev_scores_data, nfl_events_data):
    # Check if the nfl_events_data contains leagues and events
    events_data = nfl_events_data.get('events', [])

    if not events_data:
        print("No events data found.")
        return dash.no_update, False

    # Filter games that are in progress
    game_ids = [
        event.get('id') for event in events_data
        if event['status']['type']['description'].lower() == "in progress"
    ]

    # If no games are in progress, we don't need to fetch data
    if not game_ids:
        print("No games in progress.")
        return dash.no_update, False

    print(f"Fetching live data for game IDs: {game_ids}")

    updated_scores_data = []
    games_in_progress = False

    # Fetch live data for each in-progress game using fetch_game_scoreboard(game_id)
    for game_id in game_ids:
        game_data = fetch_game_scoreboard(game_id)

        if not game_data:
            print(f"Error fetching live scores for game ID {game_id}")
            continue

        # Extract relevant fields from the game_data
        game_info = game_data.get('event', {})
        competitions = game_info.get('competitions', [])

        if not competitions:
            print(f"No competition data found for game ID {game_id}")
            continue

        home_team = competitions[0]['competitors'][0]['team']['displayName']
        away_team = competitions[0]['competitors'][1]['team']['displayName']

        home_score = competitions[0]['competitors'][0].get('score', 'N/A')
        away_score = competitions[0]['competitors'][1].get('score', 'N/A')

        # Get the quarter and remaining time from the status
        status_info = game_info.get('status', {})
        quarter = status_info.get('period', 'N/A')
        situation = status_info.get('situation', {})
        time_remaining = status_info.get('displayClock', 'N/A')
        game_status = status_info.get('type', {}).get('description', 'N/A')
        possesion = situation.get('downDistanceText', 'N/A')
        possession_team = situation.get('possession', {}).get('displayName', 'N/A')

        # If game is in progress, mark as true
        if game_status.lower() == "in progress":
            games_in_progress = True

        # Append the extracted data to the updated scores data
        updated_scores_data.append({
            'game_id': game_id,
            'Home Team Score': home_score,
            'Away Team Score': away_score,
            'Quarter': quarter,
            'Time Remaining': time_remaining,
            'Down Distance': possesion,
            'Possession': possession_team,
        })
        print(f"{home_team} vs {away_team}: {quarter} quarter, {time_remaining}")

    # Compare the new scores with the previous ones to avoid unnecessary updates
    if prev_scores_data == updated_scores_data:
        print("No score changes, not updating.")
        return dash.no_update, games_in_progress

    return updated_scores_data, games_in_progress


def get_scoring_plays(game_id):
    # print(f"Fetching scoring plays for game ID: {game_id}")
    querystring = {"id": game_id}
    response = requests.get(SCORINGPLAYS_URL, headers=HEADERS, params=querystring)

    if response.status_code == 200:
        scoring_data = response.json()
        # print("Scoring Data:", scoring_data)

        # Get the scoring plays list
        scoring_plays = scoring_data.get('scoringPlays', [])
        formatted_scoring_plays = []

        # Iterate over the list of scoring plays
        for play in scoring_plays:
            team_logo = play['team'].get('logo', '')
            period = play.get('period', {}).get('number', '')
            clock = play.get('clock', {}).get('displayValue', '')
            text = play.get('text', '')
            away_score = play.get('awayScore', '')
            home_score = play.get('homeScore', '')

            # Format each scoring play
            formatted_play = html.Div([
                html.Img(src=team_logo, height="30px", style={'margin-right': '10px'}),
                html.Span(f"Q{period} {clock} - "),
                html.Span(text),
                html.Span(f" ({away_score} - {home_score})", style={'margin-left': '10px'})
            ], style={'display': 'flex', 'align-items': 'center'})

            formatted_scoring_plays.append(formatted_play)

        return formatted_scoring_plays
    else:
        return []  # Return empty list if the API call fails


@app.callback(
    Output({'type': 'scoring-plays', 'index': dash.dependencies.ALL}, 'children'),
    [Input({'type': 'game-button', 'index': dash.dependencies.ALL}, 'n_clicks')],
    [State({'type': 'game-button', 'index': dash.dependencies.ALL}, 'id')]
)
def display_scoring_plays(n_clicks_list, button_ids):
    ctx = dash.callback_context
    if not ctx.triggered:
        return [[]] * len(n_clicks_list)

    # Get the triggered button ID
    triggered_button = ctx.triggered[0]['prop_id'].split('.')[0]
    game_id = json.loads(triggered_button)['index']  # Get the game ID from button ID

    # Fetch and display scoring plays for the selected game
    scoring_plays = get_scoring_plays(game_id)

    # Ensure the scoring plays are displayed for the correct game button
    outputs = []
    for i, button_id in enumerate(button_ids):
        if n_clicks_list[i] % 2 == 1:  # Show scoring plays if clicked
            outputs.append(scoring_plays)
        else:
            outputs.append([])  # Hide scoring plays if not clicked

    return outputs



last_fetched_odds = load_last_fetched_odds()
# Dash layout setup
app.layout = dbc.Container([
    INTERVAL_SCORES,  # Add scores interval
    INTERVAL_ODDS,    # Add odds interval
    dbc.Row(dbc.Col(html.H1("NFL Games"), className="text-center")),
    dcc.Store(id='in-progress-flag', data=False),  # Store to track if games are in progress
    dcc.Store(id='selected-week', data={'value': None}),  # Store selected week in dcc.Store
    dcc.Store(id='week-options-store', data=False),  # Add dcc.Store for week options
    dcc.Store(id='scores-data', data=[]) , # Use dcc.Store
    dcc.Store(id='nfl-events-data', data={}),  # New Store for NFL events data
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

if __name__ == "__main__":
    app.run_server(debug=True, port=port)