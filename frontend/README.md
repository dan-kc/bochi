# Tofustash Frontend

A local-first React Native application for Web, Android, and iOS.

## Development

Run all commands from the **project root** (not from the frontend directory). Node is only available through the nix devshell wrappers.

### Commands

- `npm run web` - Start web development server
- `npm run lint` - Run ESLint
- `npm run typecheck` - Run TypeScript type checking
- `npm start` - Start Expo development server

### Architecture

- **React Native / Expo** - Cross-platform mobile and web framework
- **Local-first sync** - Habits and trades sync to the server when online, work offline
- **Entity stores** - State management using `useSyncExternalStore` pattern

### Key Directories

- `app/` - Expo Router pages and layouts
- `components/` - Reusable UI components
- `lib/` - Core logic, stores, sync, and utilities
  - `store/` - Entity stores (habitStore, tradeStore, etc.)
  - `sync/` - Sync service and storage
