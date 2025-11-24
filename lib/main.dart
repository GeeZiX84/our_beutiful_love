import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

void main() {
  runApp(const LoveApp());
}

class LoveApp extends StatelessWidget {
  const LoveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
      theme: ThemeData(
        fontFamily: "Arial",
        scaffoldBackgroundColor: Color(0xFFFFF0F6),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: Colors.pinkAccent,
        ),
      ),
    );
  }
}

// Дата отношений
final DateTime startDate = DateTime(2025, 10, 26);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Duration since = Duration.zero;
  Timer? timer;

  int loveCount = 8;

  @override
  void initState() {
    super.initState();
    loadCounter();
    startTimer();
  }

  void startTimer() {
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        since = DateTime.now().difference(startDate);
      });
    });
  }

  Future<void> loadCounter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      loveCount = prefs.getInt("loveCount") ?? 0;
    });
  }

  Future<void> incrementCounter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      loveCount++;
    });
    prefs.setInt("loveCount", loveCount);
  }

  @override
  Widget build(BuildContext context) {
    final days = since.inDays;
    final hours = since.inHours % 24;
    final minutes = since.inMinutes % 60;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Наше Любовное Приложение ❤️",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.pinkAccent,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Таймер
              Text(
                "Мы вместе уже:",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink[700],
                ),
              ),

              const SizedBox(height: 10),

              Text(
                "$days дней\n$hours часов\n$minutes минут",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 40),

              // Счётчик "я люблю тебя"
              Text(
                "Сколько раз мы сказали «я люблю тебя»:",
                style: TextStyle(
                  fontSize: 22,
                  color: Colors.pink[600],
                ),
              ),

              const SizedBox(height: 10),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: anim,
                  child: child,
                ),
                child: Text(
                  "$loveCount",
                  key: ValueKey(loveCount),
                  style: const TextStyle(
                    fontSize: 50,
                    fontWeight: FontWeight.bold,
                    color: Colors.pinkAccent,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: incrementCounter,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 30, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  "Сказать «я люблю тебя» ❤️",
                  style: TextStyle(fontSize: 20),
                ),
              ),

              const SizedBox(height: 40),

              // Кнопка для перехода на экран с посланием
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MessageScreen()),
                  );
                },
                child: Text(
                  "Перейти к посланию 💌",
                  style: TextStyle(
                    color: Colors.pink[800],
                    fontSize: 20,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MessageScreen extends StatelessWidget {
  const MessageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF0F6),
      appBar: AppBar(
        title: const Text("Моё послание 💗"),
        backgroundColor: Colors.pinkAccent,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            "Напиши своё послание здесь ❤️",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}
