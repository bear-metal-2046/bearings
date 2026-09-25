import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);

  runApp(const BeariscribeApp());
}

class BeariscribeApp extends StatelessWidget {
  const BeariscribeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beariscribe',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.lightGreen,
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const BeariscribeWindow(),
    );
  }
}

class BeariscribeWindow extends StatefulWidget {
  const BeariscribeWindow({super.key});

  @override
  State<BeariscribeWindow> createState() => _BeariscribeWindowState();
}

class _BeariscribeWindowState extends State<BeariscribeWindow>
    with WindowListener {
  bool isMaximized = false;

  @override
  void initState() {
    super.initState();

    windowManager.addListener(this);
    _updateMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _updateMaximizedState() async {
    final maximized = await windowManager.isMaximized();

    if (mounted) {
      setState(() {
        isMaximized = maximized;
      });
    }
  }

  @override
  void onWindowMaximize() {
    setState(() {
      isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      isMaximized = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(40),
        child: Container(
          color: colors.primary,
          child: Row(
            children: [
              Expanded(
                child: DragToMoveArea(
                  child: Container(
                    height: 40,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      'Beariscribe',
                      style: TextStyle(
                        color: colors.onPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),

              WindowCaptionButton.minimize(
                brightness: Brightness.dark,
                onPressed: windowManager.minimize,
              ),
              if (isMaximized)
                WindowCaptionButton.unmaximize(
                  brightness: Brightness.dark,
                  onPressed: windowManager.unmaximize,
                )
              else
                WindowCaptionButton.maximize(
                  brightness: Brightness.dark,
                  onPressed: windowManager.maximize,
                ),
              WindowCaptionButton.close(
                brightness: Brightness.dark,
                onPressed: windowManager.close,
              ),
            ],
          ),
        ),
      ),
      body: const Center(
        child: Text('Beariscribe'),
      ),
    );
  }
}