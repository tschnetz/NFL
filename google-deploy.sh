# Log in to the Google Cloud Console: https://console.cloud.google.com/.
  #	2.	Create a new project:
  #	•	Go to the project selector and click New Project.
  #	•	Give your project a name and note down the project ID.
# Create a Dockerfile in the root of your project directory
docker build -t streamlit-app .
# gcloud auth login
gcloud config set project nfl-app-437604
gcloud builds submit --tag gcr.io/nfl-app-437604/streamlit-app
gcloud run deploy streamlit-app --image gcr.io/nfl-app-437604/streamlit-app --platform managed --region us-east1 --allow-unauthenticated