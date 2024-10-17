# Log in to the Google Cloud Console: https://console.cloud.google.com/.
  #	2.	Create a new project:
  #	•	Go to the project selector and click New Project.
  #	•	Give your project a name and note down the project ID.
# Create a Dockerfile in the root of your project directory
docker build --platform linux/amd64 -t nfl-app .
# gcloud auth login
gcloud config set project nfl-data-2024
gcloud builds submit --tag gcr.io/nfl-data-2024/nfl-app
gcloud run deploy nfl-app --image gcr.io/nfl-data-2024/nfl-app --platform managed --region us-east1 --allow-unauthenticated