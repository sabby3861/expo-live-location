import { registerRootComponent } from 'expo';

import App from './App';

// registerRootComponent calls AppRegistry.registerComponent('main', () => App).
// It also ensures that whether the app loads in Expo Go or a native build, the
// environment is set up appropriately.
registerRootComponent(App);
