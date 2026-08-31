# TRAZA

App móvil de running con gamificación e IA

## Requisitos

- Flutter (canal stable) instalado y en el PATH
- Cuenta de Google con acceso al proyecto Firebase `traza-47f50`
- Android Studio o Xcode, según la plataforma en la que vayas a correr la app

## Cómo correr el proyecto

```bash
git clone https://github.com/tu-org/traza.git
cd traza
flutter pub get
flutter run
```

No necesitas correr `flutterfire configure` — `lib/firebase_options.dart` y los archivos nativos ya están en el repo. Si Firebase te agrega como colaborador del proyecto, ya puedes autenticarte y ver datos reales en Firestore.

## Estructura de carpetas

```
lib/
├── main.dart
├── firebase_options.dart          # generado por flutterfire configure — no tocar a mano
├── models/                        # Usuario, Objetivo, Entrenamiento, PuntoGps, etc.
├── services/                      # auth_service.dart, firestore_service.dart, location_service.dart
├── screens/
│   ├── auth/                      # login, register, forgot_password
│   ├── onboarding/                # permissions, goals
│   ├── home/                      # home (selección de actividad + iniciar)
│   ├── tracking/                  # cronómetro + mapa + distancia en vivo
│   ├── summary/                   # resumen del entrenamiento
│   └── history/                   # historial de entrenamientos
└── widgets/                       # componentes reutilizables (chips, cards, botones)
```

## Convención de ramas

Una rama por historia de Jira, usando el ID del issue:

```
feature/TRAZA-12-registro-correo
feature/TRAZA-13-registro-google
fix/TRAZA-20-validacion-permisos
```

Pull request hacia `develop`, no directo a `main`. `main` se reserva para lo que ya pasó QA.

## Firestore

Las reglas de seguridad viven en `firestore.rules` en la raíz del repo. Para desplegarlas:

```bash
firebase deploy --only firestore:rules
```

Cualquier cambio al modelo de datos (nueva colección, nuevo campo con reglas propias) debe venir acompañado de un cambio a este archivo en el mismo PR.
