# 🧭 Flutter Navigation App with Geotriggers & Voice Alerts
![Wonders Map App](https://img.shields.io/badge/platform-Flutter-blue) [![LinkedIn](https://img.shields.io/badge/LinkedIn-Connect-blue)](https://www.linkedin.com/in/martino-yovo/) ![GitHub followers](https://img.shields.io/github/followers/martinoyovo) ![X Follow](https://img.shields.io/twitter/follow/martinoyovo.svg?style=social)

A Flutter application that showcases wonders around the world using  for seamless map integration.
This project is a Flutter-based navigation app that demonstrates geospatial awareness using Geotriggers, real-time route tracking, and voice alerts. Built with the [ArcGIS Maps SDK for Flutter](https://pub.dev/packages/arcgis_maps), it simulates a smart navigation experience designed for spatially aware applications.

You can learn more about how this app was built by reading my post on ArcGIS Blog: [Build smarter location-aware apps with Geotriggers in ArcGIS Maps SDK for Flutter](https://www.esri.com/arcgis-blog/).

## 📱 Features Overview
1. Load a map and preview route
2. Use Geotriggers to detect entry and exit of warning zones
3. Play voice alerts when entering or exiting geofenced areas
4. Update the route progress and warnings in the UI
5. Intuitive controls and custom widgets for navigation

## Preview
![Wonders Map App](screenshots/demo.gif)
|              Initial view             |             Expand Page           |             Map Selection           |
| :----------------------------------: | :----------------------------------: | :----------------------------------: |
| <img src="https://raw.githubusercontent.com/martinoyovo/geo_navigation_flutter/refs/heads/main/screens_and_demos/1.png" width="350"> | <img src="https://raw.githubusercontent.com/martinoyovo/geo_navigation_flutter/refs/heads/main/screens_and_demos/2.png" width="350"> | <img src="https://raw.githubusercontent.com/martinoyovo/geo_navigation_flutter/refs/heads/main/screens_and_demos/3.png" width="350"> |

## Full video
<video src="demo.mp4" controls width="100%"></video>

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/martinoyovo/geo_navigation_flutter.git
cd geo_navigation_flutter
```

### 2. Install ArcGIS Maps Core

Run the following command to install the necessary ArcGIS dependencies:

```bash
dart run arcgis_maps install
```

> ⚠️ Note for Windows Users:
> 
> 
> This step requires permission to create symbolic links. Either:
> 
- Run the command in an elevated **Administrator Command Prompt**, or
- Enable **Developer Mode** by going to:
    
    `Settings > Update & Security > For Developers` and turning on **Developer Mode**.
    

---

## 🔑 Configure an API Key

To enable map functionality, you need to generate an **API Key** with appropriate privileges.

1. Follow the [Create an API Key Tutorial](https://developers.arcgis.com/documentation/mapping-apis-and-services/security/api-keys/).
2. Ensure that you set the **Location Services** privileges to **Basemap**.
3. Copy the generated API key, as it will be used in the next step.

---

### 3. Create `env.json`

Create a file named `env.json` in the root directory of your project with the following format:

```json
{
    "API_KEY": "your_api_key_here"
}
```

---

## 🛠️ Run the Project

### 4. Clean and Install Dependencies

```bash
flutter clean && flutter pub get
```

### 5. Run the Application

To run the app using the `env.json` file, use:

```bash
flutter run --dart-define-from-file=path/to/env.json
```

## 📚 System Requirements

- **Dart:** 3.7.0+
- **Flutter:** 3.29.0+
- ArcGIS Maps SDK properly configured for map rendering. 

For more information, view the detailed [system requirements](https://developers.arcgis.com/flutter/system-requirements/system-requirements-for-200-7/)
