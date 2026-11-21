import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { useEffect, useState } from 'react';
import { Linking, Pressable, Settings, Text, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

// Tap "Remount" (or open rnsrepro://remount) to unmount the navigator and mount a new one.
// Launch options (iOS launch arguments, read through Settings), to try the shapes:
//   -remount same       key change in one commit (default)
//   -remount gap        one commit with no navigator, then the new navigator
//   -remount interlude  a plain full-screen screen for 1 s, then the new navigator
//   -wrapper view       the navigator sits in a full-screen View (collapsable={false}) that is remounted with it
//   -wrapper alternate  that View is there only on odd generations: the first mount has none, the first remount adds it
const REMOUNT: string = Settings.get('remount') ?? 'same';
const WRAPPER: string = Settings.get('wrapper') ?? 'none';

const Stack = createNativeStackNavigator();

function HeaderTitle() {
  return (
    <View>
      <Text>Title</Text>
    </View>
  );
}

function HeaderRight() {
  return (
    <Pressable accessibilityRole="button" onPress={() => {}}>
      <Text>Right</Text>
    </Pressable>
  );
}

function makeHome(generation: number, remount: () => void) {
  return function Home() {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: 16 }}>
        <Text>Navigator generation {generation}</Text>
        <Text>
          remount={REMOUNT} wrapper={WRAPPER}
        </Text>
        <Pressable accessibilityRole="button" onPress={remount}>
          <Text>Remount</Text>
        </Pressable>
      </View>
    );
  };
}

function Interlude() {
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', gap: 8 }}>
      <View>
        <Text>Interlude</Text>
      </View>
      <View>
        <Text>One moment</Text>
      </View>
    </View>
  );
}

export default function App() {
  const [generation, setGeneration] = useState(0);
  const [phase, setPhase] = useState<'nav' | 'gap' | 'interlude'>('nav');

  const remount = () => {
    if (REMOUNT === 'same') {
      setGeneration((g) => g + 1);
      return;
    }
    setPhase(REMOUNT === 'interlude' ? 'interlude' : 'gap');
    setTimeout(
      () => {
        setGeneration((g) => g + 1);
        setPhase('nav');
      },
      REMOUNT === 'interlude' ? 1000 : 100,
    );
  };

  useEffect(() => {
    const sub = Linking.addEventListener('url', ({ url }) => {
      if (url.includes('remount')) remount();
    });
    return () => sub.remove();
  }, []);

  let content = null;
  if (phase === 'interlude') {
    content = <Interlude />;
  } else if (phase === 'nav') {
    const Home = makeHome(generation, remount);
    const navigator = (
      <NavigationContainer key={generation}>
        <Stack.Navigator>
          <Stack.Screen
            name="Home"
            component={Home}
            options={{
              headerTitle: () => <HeaderTitle />,
              headerRight: () => <HeaderRight />,
            }}
          />
        </Stack.Navigator>
      </NavigationContainer>
    );
    const wrapped = WRAPPER === 'view' || (WRAPPER === 'alternate' && generation % 2 === 1);
    content = wrapped ? (
      <View key={generation} collapsable={false} style={{ flex: 1 }}>
        {navigator}
      </View>
    ) : (
      navigator
    );
  }

  return <SafeAreaProvider>{content}</SafeAreaProvider>;
}
