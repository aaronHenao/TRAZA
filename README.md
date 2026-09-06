# TRAZA

App móvil de running con gamificación e IA — Universidad de Medellín, Gestión de Proyectos Informáticos.

## Stack

- **Frontend:** Flutter
- **Backend:** Supabase (Postgres) -> BaaS

## Requisitos

- Flutter (canal stable) instalado y en el PATH
- Cuenta de Supabase con acceso al proyecto `traza`
- Android Studio o Xcode, según la plataforma en la que vayas a correr la app

## Cómo correr el proyecto

```bash
git clone https://github.com/aaronHenao/TRAZA
cd traza
flutter pub get
flutter run
```

La URL y la publishable key de Supabase ya están en `lib/supabase_config.dart`, committeadas directo en el repo — como es privado y solo somos nosotros 4, no vale la pena montar `.env` ni `--dart-define` para esto. Esa key **no es secreta** (está pensada para ir en apps cliente, se protege con Row Level Security, no ocultándola).

**Nunca** subas al repo la **secret key** de Supabase (la que reemplaza a `service_role`) — esa da acceso total a la base de datos saltándose RLS. No la necesitamos para nada de lo que hace la app hoy.

## Estructura de carpetas

```
lib/
├── main.dart
├── supabase_config.dart           # URL + publishable key
├── models/                        # Perfil, Objetivo, Entrenamiento, PuntoGps, etc.
├── services/                      # auth_service.dart, entrenamiento_service.dart, location_service.dart
├── screens/
│   ├── auth/                      # login, register, forgot_password
│   ├── onboarding/                # permissions, goals
│   ├── home/                      # home (selección de actividad + iniciar)
│   ├── tracking/                  # cronómetro + mapa + distancia en vivo
│   ├── summary/                   # resumen del entrenamiento
│   └── history/                   # historial de entrenamientos
└── widgets/                       # componentes reutilizables (chips, cards, botones)

supabase/
└── migrations/                    # historial versionado del esquema, en orden
    ├── 0001_init_sprint1.sql
    └── 0002_perfiles.sql
```

## Base de datos (Supabase)

Compartimos **un solo proyecto de Supabase** entre los 4 — no cada quien tiene su propia base de datos local. Por eso las migraciones de `supabase/migrations/` no las corre cada uno al clonar el repo, sino que **una sola persona las aplica una vez** desde el SQL Editor del dashboard, y todos trabajamos contra esa misma base.

Si necesitas cambiar el esquema (nueva tabla, nueva columna, nueva política):

1. Escribe el cambio como un archivo nuevo y numerado en `supabase/migrations/` (ej. `0003_algo.sql`) — nunca edites un archivo de migración ya aplicado.
2. Avisa en el grupo antes de correrlo en el SQL Editor, para que no se pisen cambios entre dos personas al mismo tiempo.
3. Sube el archivo `.sql` en el mismo PR donde usas esa tabla/columna nueva desde Flutter.

## Convención de ramas

Una rama por historia de Jira, usando el ID del issue:

```
feature/TRAZA-12-registro-correo
feature/TRAZA-13-registro-google
fix/TRAZA-20-validacion-permisos
```

Pull request hacia `develop`, no directo a `main`. `main` se reserva para lo que ya pasó QA.