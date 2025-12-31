import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const LoveApp());
}

/* ================= APP ================= */

class LoveApp extends StatelessWidget {
  const LoveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B9D),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: kIsWeb ? 'Segoe UI, -apple-system, Roboto, sans-serif' : null,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B9D),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: kIsWeb ? 'Segoe UI, -apple-system, Roboto, sans-serif' : null,
      ),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

/* ================= AUTH ================= */

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? ok;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() => ok = p.getBool('auth') ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    
    if (ok == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFFFF7FA),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HeartPulseAnimation(size: 80),
              const SizedBox(height: 20),
              Text(
                'Загрузка любви... 💘',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFFFF6B9D),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ok! ? const RoleScreen() : const BeautifulAuthScreen();
  }
}

/* ================= BEAUTIFUL AUTH SCREEN (ECDH) ================= */

class BeautifulAuthScreen extends StatefulWidget {
  const BeautifulAuthScreen({super.key});

  @override
  State<BeautifulAuthScreen> createState() => _BeautifulAuthScreenState();
}

class _BeautifulAuthScreenState extends State<BeautifulAuthScreen>
    with TickerProviderStateMixin {
  final TextEditingController _dayController = TextEditingController();
  final TextEditingController _monthController = TextEditingController();
  final FocusNode _dayFocus = FocusNode();
  final FocusNode _monthFocus = FocusNode();

  String _error = '';
  bool _isLoading = false;
  late AnimationController _shakeController;
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;

  static final Map<String, ECPoint> _pointCache = {};
  static const int _prime = 4013;

  @override
  void initState() {
    super.initState();
    
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat(reverse: true);
    
    _floatAnimation = Tween(begin: -8.0, end: 8.0).animate(
      CurvedAnimation(
        parent: _floatController,
        curve: Curves.easeInOut,
      ),
    );
  }

  bool _isPointOnCurve(ECPoint point, int a, int b) {
    final left = (point.y * point.y) % _prime;
    final x2 = point.x * point.x % _prime;
    final x3 = x2 * point.x % _prime;
    final right = (x3 + a * point.x + b) % _prime;
    return left == right;
  }

  ECPoint _addPoints(ECPoint p1, ECPoint p2, int a) {
    if (p1.isInfinity) return p2;
    if (p2.isInfinity) return p1;
    
    if (p1.x == p2.x && (p1.y + p2.y) % _prime == 0) {
      return ECPoint.infinity();
    }
    
    int lambda;
    final modPrime = _prime;
    
    if (p1.x == p2.x && p1.y == p2.y) {
      final numerator = (3 * p1.x * p1.x + a) % modPrime;
      final denominator = (2 * p1.y) % modPrime;
      final denominatorInverse = _modInverse(denominator, modPrime);
      lambda = (numerator * denominatorInverse) % modPrime;
    } else {
      final numerator = (p2.y - p1.y) % modPrime;
      final denominator = (p2.x - p1.x) % modPrime;
      final denominatorInverse = _modInverse(denominator, modPrime);
      lambda = (numerator * denominatorInverse) % modPrime;
    }
    
    final x3 = (lambda * lambda - p1.x - p2.x) % modPrime;
    final y3 = (lambda * (p1.x - x3) - p1.y) % modPrime;
    
    return ECPoint(x3, y3);
  }

  ECPoint _multiplyPoint(ECPoint point, int scalar, int a) {
    final cacheKey = '${point.x},${point.y},$scalar,$a';
    if (_pointCache.containsKey(cacheKey)) {
      return _pointCache[cacheKey]!;
    }
    
    ECPoint result = ECPoint.infinity();
    ECPoint addend = point;
    int s = scalar;
    
    while (s > 0) {
      if (s & 1 == 1) {
        result = _addPoints(result, addend, a);
      }
      addend = _addPoints(addend, addend, a);
      s >>= 1;
    }
    
    _pointCache[cacheKey] = result;
    return result;
  }

  int _modInverse(int a, int m) {
    int m0 = m, y = 0, x = 1;
    if (m == 1) return 0;
    
    while (a > 1) {
      final q = a ~/ m;
      int t = m;
      m = a % m;
      a = t;
      t = y;
      y = x - q * y;
      x = t;
    }
    
    if (x < 0) x += m0;
    return x;
  }

  Future<ECPoint> _generateSecretPoint(int day, int month) async {
    final cacheKey = '$day-$month';
    if (_pointCache.containsKey(cacheKey)) {
      return _pointCache[cacheKey]!;
    }
    
    final a = day;
    final b = month;
    
    ECPoint? basePoint;
    final limit = math.min(_prime, 800);
    
    for (int x = 1; x < limit; x++) {
      final x2 = x * x % _prime;
      final x3 = x2 * x % _prime;
      final right = (x3 + a * x + b) % _prime;
      
      for (int y = 1; y < limit; y++) {
        if ((y * y) % _prime == right) {
          basePoint = ECPoint(x, y);
          break;
        }
      }
      if (basePoint != null) break;
    }
    
    if (basePoint == null) {
      basePoint = ECPoint(1, (1 + a + b) % _prime);
    }
    
    final secretMultiplier = (day * 31 + month) % _prime;
    final result = _multiplyPoint(basePoint, secretMultiplier, a);
    
    _pointCache[cacheKey] = result;
    return result;
  }

  Future<void> _checkAuth() async {
    final day = int.tryParse(_dayController.text);
    final month = int.tryParse(_monthController.text);

    if (day == null || month == null || day < 1 || day > 31 || month < 1 || month > 12) {
      setState(() => _error = 'Введите корректную дату (день 1-31, месяц 1-12) 💔');
      _shakeController.forward(from: 0);
      return;
    }

    setState(() {
      _error = '';
      _isLoading = true;
    });

    try {
      final secretPoint = await _generateSecretPoint(day, month);
      
      final firestore = FirebaseFirestore.instance;
      final pointRef = firestore.collection('auth').doc('curvePoint');
      final doc = await pointRef.get();
      
      if (!doc.exists) {
        await pointRef.set({
          'x': secretPoint.x,
          'y': secretPoint.y,
          'a': day,
          'b': month,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('auth', true);

        if (!mounted) return;
        _navigateToRoleScreen();
      } else {
        final storedPoint = ECPoint(
          (doc['x'] as num).toInt(),
          (doc['y'] as num).toInt(),
        );
        final storedA = (doc['a'] as num).toInt();
        final storedB = (doc['b'] as num).toInt();

        if (_isPointOnCurve(storedPoint, day, month) &&
            storedA == day && storedB == month) {
          
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('auth', true);

          if (!mounted) return;
          _navigateToRoleScreen();
        } else {
          setState(() => _error = 'Неверная дата 💔 Попробуйте еще раз');
          _shakeController.forward(from: 0);
          if ((await Vibration.hasVibrator()) == true) {
            Vibration.vibrate(duration: 150);
          }
        }
      }
    } catch (e) {
      setState(() => _error = 'Ошибка подключения 📶 Проверьте интернет');
      _shakeController.forward(from: 0);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToRoleScreen() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const RoleScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFFFF7FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                final offset = _shakeController.value *
                    math.sin(_shakeController.value * 4 * math.pi) * 8;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: child,
                );
              },
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: isDark 
                          ? Colors.black.withOpacity(0.3) 
                          : const Color(0xFFFF6B9D).withOpacity(0.1),
                      blurRadius: 30,
                      spreadRadius: 2,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Анимированное сердце
                    AnimatedBuilder(
                      animation: _floatAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _floatAnimation.value),
                          child: child,
                        );
                      },
                      child: const HeartPulseAnimation(size: 100),
                    ),
                    
                    const SizedBox(height: 28),
                    
                    // Заголовок
                    Text(
                      'Тайна нашей любви 💖',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Подзаголовок
                    Text(
                      'Введите день и месяц начала нашей истории 💑',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? Colors.white70 : const Color(0xFF666666),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Поля ввода
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildDateField(
                          controller: _dayController,
                          focusNode: _dayFocus,
                          hint: 'День',
                          nextFocus: _monthFocus,
                          isDark: isDark,
                        ),
                        
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '❤️',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        
                        _buildDateField(
                          controller: _monthController,
                          focusNode: _monthFocus,
                          hint: 'Месяц',
                          onSubmit: _checkAuth,
                          isDark: isDark,
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Подсказка
                    Text(
                      'Например: ээээ не скажу ихиххихи✨',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white60 : const Color(0xFF999999),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    
                    const SizedBox(height: 36),
                    
                    // Кнопка входа
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _checkAuth,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B9D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 4,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Открыть сердце',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('💝'),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 20,
                                  ),
                                ],
                              ),
                      ),
                    ),
                    
                    // Ошибка
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2D1A1A) : const Color(0xFFFFF0F0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Text('💔', style: TextStyle(color: isDark ? Colors.white : null)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _error,
                                style: TextStyle(
                                  color: isDark ? const Color(0xFFF44336) : const Color(0xFFD32F2F),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 24),
                    
                    // Формула (декоративная)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'y² = x³ + ax + b mod 4013 💫',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white70 : const Color(0xFF777777),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required bool isDark,
    FocusNode? nextFocus,
    VoidCallback? onSubmit,
  }) {
    return Container(
      width: 100,
      height: 64,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF6B9D).withOpacity(isDark ? 0.5 : 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.3)
                : const Color(0xFFFF6B9D).withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 2,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFFF6B9D),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFF6B9D).withOpacity(isDark ? 0.5 : 0.3),
          ),
          counterText: '',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(20),
        ),
        onChanged: (value) {
          if (value.length == 2 && nextFocus != null) {
            FocusScope.of(context).requestFocus(nextFocus);
          }
        },
        onSubmitted: (_) {
          if (onSubmit != null) {
            onSubmit();
          } else if (nextFocus != null) {
            FocusScope.of(context).requestFocus(nextFocus);
          }
        },
      ),
    );
  }
}

/* ================= HEART PULSE ANIMATION ================= */
class HeartPulseAnimation extends StatefulWidget {
  final double size;
  final Color? color;

  const HeartPulseAnimation({
    super.key,
    required this.size,
    this.color,
  });

  @override
  State<HeartPulseAnimation> createState() => _HeartPulseAnimationState();
}

class _HeartPulseAnimationState extends State<HeartPulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 0.96), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.0), weight: 1),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFF6B9D),
                  Color(0xFFFFA8C5),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B9D).withOpacity(isDark ? 0.5 : 0.3),
                  blurRadius: 15,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}

/* ================= BEAUTIFUL ROLE SCREEN ================= */
class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key});

  Future<void> _setRole(BuildContext context, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('role', role);
    
    if (!context.mounted) return;
    
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFFFF7FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: isDark 
                        ? Colors.black.withOpacity(0.3) 
                        : const Color(0xFFFF6B9D).withOpacity(0.1),
                    blurRadius: 30,
                    spreadRadius: 2,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Анимированное сердце
                  const HeartPulseAnimation(size: 100),
                  
                  const SizedBox(height: 28),
                  
                  // Заголовок
                  Text(
                    'Кто вы в этой истории? 💑',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF333333),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Подзаголовок
                  Text(
                    'Выберите свою роль в любви 💘',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white70 : const Color(0xFF666666),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Кнопка Любимый
                  _buildRoleButton(
                    icon: Icons.person,
                    label: 'Любимый 💙',
                    description: 'Тот, кто дарит любовь и заботу 💝\nХранитель её сердца 👑',
                    color: const Color(0xFF4A90E2),
                    onTap: () => _setRole(context, 'loved'),
                    isDark: isDark,
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Кнопка Любимая
                  _buildRoleButton(
                    icon: Icons.person_outline,
                    label: 'Любимая 💗',
                    description: 'Та, кто вдохновляет и очаровывает ✨\nСолнце в его небе ☀️',
                    color: const Color(0xFFFF6B9D),
                    onTap: () => _setRole(context, 'beloved'),
                    isDark: isDark,
                  ),
                  
                  const SizedBox(height: 30),
                  
                  // Романтичная подпись
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Выберите, кто вы в этой сказке любви 🏰\nГде каждый день — новая страница истории 📖',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : const Color(0xFF777777),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleButton({
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withOpacity(isDark ? 0.3 : 0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    color: color,
                    size: 28,
                  ),
                ),
              ),
              
              const SizedBox(width: 20),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : const Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: color.withOpacity(isDark ? 0.7 : 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ================= ECPOINT CLASS ================= */
class ECPoint {
  final int x;
  final int y;
  final bool isInfinity;

  const ECPoint(this.x, this.y) : isInfinity = false;

  const ECPoint.infinity()
      : x = 0,
        y = 0,
        isInfinity = true;

  @override
  String toString() => isInfinity ? '∞' : '($x, $y)';
}

/* ================= HOME WITH TABS ================= */

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final DateTime _startDate = DateTime(2025, 10, 26);
  late AnimationController _heartController;
  late TabController _tabController;
  
  String _role = 'loved';
  int _totalLoves = 0;
  String _timer = '';
  bool _isTapping = false;
  Timer? _updateTimer;
  bool _nightMode = false;
  bool _quietMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    _listenToLoveCount();
    _startTimer();

    _heartController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPrefs();
      _listenToLoveCount();
    }
  }

  void _startTimer() {
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateTimerText();
      }
    });
    _updateTimerText();
  }

  void _updateTimerText() {
    final duration = DateTime.now().difference(_startDate);
    final months = (duration.inDays / 30).floor();
    final days = duration.inDays % 30;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (mounted) {
      setState(() {
        _timer = '$months мес $days дн $hours час $minutes мин $seconds сек';
      });
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _role = prefs.getString('role') ?? 'loved';
          _nightMode = prefs.getBool('night') ?? false;
          _quietMode = prefs.getBool('quiet') ?? false;
        });
      }
    } catch (_) {}
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('night', _nightMode);
      await prefs.setBool('quiet', _quietMode);
    } catch (_) {}
  }

  void _listenToLoveCount() {
    FirebaseFirestore.instance
        .collection('love')
        .doc('shared')
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;
      if (mounted) {
        setState(() {
          final loved = snapshot['fromLoved'] ?? 0;
          final beloved = snapshot['fromBeloved'] ?? 0;
          _totalLoves = loved + beloved;
        });
      }
    }, onError: (_) {});
  }

  Future<void> _tapHeart() async {
    if (_isTapping || _quietMode) return;
    
    setState(() => _isTapping = true);
    
    if ((await Vibration.hasVibrator()) == true) {
      try {
        Vibration.vibrate(duration: 20);
      } catch (_) {}
    }

    final firestore = FirebaseFirestore.instance;
    final loveRef = firestore.collection('love').doc('shared');
    final doc = await loveRef.get();
    
    if (doc.exists) {
      final loved = doc['fromLoved'] ?? 0;
      final beloved = doc['fromBeloved'] ?? 0;
      
      try {
        await loveRef.set({
          'fromLoved': _role == 'loved' ? loved + 1 : loved,
          'fromBeloved': _role == 'beloved' ? beloved + 1 : beloved,
          'lastTapped': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        setState(() => _totalLoves = _totalLoves + 1);
      } catch (_) {}
    } else {
      try {
        await loveRef.set({
          'fromLoved': _role == 'loved' ? 1 : 0,
          'fromBeloved': _role == 'beloved' ? 1 : 0,
          'lastTapped': FieldValue.serverTimestamp(),
        });
        
        setState(() => _totalLoves = 1);
      } catch (_) {}
    }

    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) {
      setState(() => _isTapping = false);
    }
  }

  Widget _buildHeartButton() {
    return GestureDetector(
      onTapDown: (_) => _tapHeart(),
      child: AnimatedBuilder(
        animation: _heartController,
        builder: (context, child) {
          final scale = _isTapping ? 1.15 : 1.0 + (_heartController.value * 0.1);
          return Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Фон сердца
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFF6B9D),
                        Color(0xFFFFA8C5),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6B9D).withOpacity(_nightMode ? 0.5 : 0.3),
                        blurRadius: 15,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
                
                // Иконка сердца
                const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 50,
                ),
                
                // Эмодзи поверх иконки
                Positioned(
                  top: 25,
                  child: Text(
                    '💖',
                    style: TextStyle(
                      fontSize: 30,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(_nightMode ? 0.1 : 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _nightMode ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _nightMode ? [] : [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: color.withOpacity(_nightMode ? 0.3 : 0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _nightMode ? Colors.white70 : color.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _nightMode ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartController.dispose();
    _updateTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _nightMode ? Brightness.dark : Brightness.light;
    final theme = brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: _nightMode ? const Color(0xFF121212) : const Color(0xFFFFF7FA),
        appBar: AppBar(
          backgroundColor: _nightMode ? Colors.black : const Color(0xFFFF6B9D),
          title: Text(
            'Наша история любви 💑',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(
                _quietMode ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() => _quietMode = !_quietMode);
                _savePrefs();
              },
            ),
            IconButton(
              icon: Icon(
                _nightMode ? Icons.light_mode : Icons.dark_mode,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() => _nightMode = !_nightMode);
                _savePrefs();
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              color: _nightMode ? Colors.black : const Color(0xFFFF6B9D),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withOpacity(0.7),
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                tabs: [
                  Tab(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.favorite, size: 16),
                            const SizedBox(width: 4),
                            const Text('💖'),
                          ],
                        ),
                        const Text(
                          'Любовь',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat, size: 16),
                            const SizedBox(width: 4),
                            const Text('💌'),
                          ],
                        ),
                        const Text(
                          'Сообщения',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.settings, size: 16),
                            const SizedBox(width: 4),
                            const Text('⚙️'),
                          ],
                        ),
                        const Text(
                          'Настройки',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildLoveTab(),
            _buildMessagesTab(),
            _buildSettingsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoveTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Таймер
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _nightMode ? const Color(0xFF2A2A2A) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: _nightMode ? [] : [
                  BoxShadow(
                    color: const Color(0xFFFF6B9D).withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.timer_rounded,
                        color: _nightMode ? Colors.white70 : const Color(0xFFFF6B9D),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Как долго мы вместе: 💕',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _nightMode ? Colors.white : const Color(0xFF333333),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _timer,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _nightMode ? Colors.white : const Color(0xFFFF6B9D),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'И это только начало! 🌟',
                    style: TextStyle(
                      fontSize: 14,
                      color: _nightMode ? Colors.white60 : const Color(0xFF666666),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Сердце
            Center(child: _buildHeartButton()),
            
            const SizedBox(height: 16),
            
            // Подпись
            Column(
              children: [
                Text(
                  _quietMode ? '🤫 Тихий режим активен' : '💖 Нажми на сердце!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _nightMode ? Colors.white : const Color(0xFFFF6B9D),
                  ),
                ),
                if (!_quietMode) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Каждое касание — признание в любви 💝\n'
                    'Ты нажал(а) уже $_totalLoves раз ❤️',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: _nightMode ? Colors.white60 : const Color(0xFF666666),
                    ),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 30),
            
            // Статистика
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              childAspectRatio: 1,
              children: [
                _buildStatCard(
                  'Всего сказано\n"Я люблю" 💬',
                  '$_totalLoves',
                  Icons.favorite,
                  const Color(0xFFFF6B9D),
                ),
                _buildStatCard(
                  'Дней вместе 📅',
                  '${DateTime.now().difference(_startDate).inDays}',
                  Icons.calendar_today,
                  const Color(0xFF4A90E2),
                ),
                _buildStatCard(
                  'Месяцев вместе 🌙',
                  '${(DateTime.now().difference(_startDate).inDays / 30).floor()}',
                  Icons.brightness_5,
                  const Color(0xFF9C27B0),
                ),
                _buildStatCard(
                  'Часов в любви ⏰',
                  '${DateTime.now().difference(_startDate).inHours}',
                  Icons.access_time,
                  const Color(0xFFFF9800),
                ),
              ],
            ),
            
            const SizedBox(height: 30),
            
            // Романтичная подпись
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _nightMode ? const Color(0xFF2A2A2A) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: _nightMode ? [] : [
                  BoxShadow(
                    color: const Color(0xFFFF6B9D).withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    '💝 Наша любовь — это:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _nightMode ? Colors.white : const Color(0xFFFF6B9D),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Бесконечное счастье каждый день 😊\n'
                    '• Теплые объятия, которые лечат душу 🤗\n'
                    '• Взгляды, которые говорят больше слов 👀\n'
                    '• Моменты, когда время хочется остановить ⏳\n'
                    '• Будущее, которое мы строим вместе 🏡',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 14,
                      color: _nightMode ? Colors.white70 : const Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _role == 'loved' 
                        ? 'Ты — её счастье, её опора, её всё 💙\nПродолжай дарить любовь каждый день!'
                        : 'Ты — его муза, его вдохновение, его солнце 💗\nПродолжай восхищать каждый его день!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _nightMode ? Colors.white : const Color(0xFF333333),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesTab() {
    return const _BeautifulMessages();
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Настройки внешнего вида
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _nightMode ? const Color(0xFF2A2A2A) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: _nightMode ? [] : [
                  BoxShadow(
                    color: const Color(0xFFFF6B9D).withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Настройки приложения ⚙️',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _nightMode ? Colors.white : const Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text(
                      'Ночной режим 🌙',
                      style: TextStyle(
                        fontSize: 16,
                        color: _nightMode ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                    subtitle: Text(
                      'Включить темную тему для романтических вечеров',
                      style: TextStyle(
                        fontSize: 14,
                        color: _nightMode ? Colors.white60 : const Color(0xFF666666),
                      ),
                    ),
                    value: _nightMode,
                    onChanged: (value) {
                      setState(() => _nightMode = value);
                      _savePrefs();
                    },
                    activeThumbColor: const Color(0xFFFF6B9D),
                  ),
                  SwitchListTile(
                    title: Text(
                      'Тихий режим 🤫',
                      style: TextStyle(
                        fontSize: 16,
                        color: _nightMode ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                    subtitle: Text(
                      'Отключить вибрацию при нажатии на сердце',
                      style: TextStyle(
                        fontSize: 14,
                        color: _nightMode ? Colors.white60 : const Color(0xFF666666),
                      ),
                    ),
                    value: _quietMode,
                    onChanged: (value) {
                      setState(() => _quietMode = value);
                      _savePrefs();
                    },
                    activeThumbColor: const Color(0xFFFF6B9D),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Информация о роли
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _nightMode ? const Color(0xFF2A2A2A) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: _nightMode ? [] : [
                  BoxShadow(
                    color: const Color(0xFFFF6B9D).withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ваша роль в любви 👑',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _nightMode ? Colors.white : const Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _role == 'loved' 
                            ? const Color(0xFF4A90E2).withOpacity(0.2) 
                            : const Color(0xFFFF6B9D).withOpacity(0.2),
                      ),
                      child: Icon(
                        _role == 'loved' ? Icons.person : Icons.person_outline,
                        color: _role == 'loved' ? const Color(0xFF4A90E2) : const Color(0xFFFF6B9D),
                        size: 28,
                      ),
                    ),
                    title: Text(
                      _role == 'loved' ? 'Любимый 💙' : 'Любимая 💗',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _nightMode ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                    subtitle: Text(
                      _role == 'loved' 
                          ? 'Тот, кто дарит любовь и заботу 💝\nХранитель её сердца 👑'
                          : 'Та, кто вдохновляет и очаровывает ✨\nСолнце в его небе ☀️',
                      style: TextStyle(
                        fontSize: 14,
                        color: _nightMode ? Colors.white60 : const Color(0xFF666666),
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const RoleScreen()),
                        );
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B9D).withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Сменить роль 🔄',
                        style: TextStyle(
                          color: _nightMode ? Colors.white : const Color(0xFFFF6B9D),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Информация о приложении
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _nightMode ? const Color(0xFF2A2A2A) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: _nightMode ? [] : [
                  BoxShadow(
                    color: const Color(0xFFFF6B9D).withOpacity(0.1),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'О нашей истории 💖',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _nightMode ? Colors.white : const Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B9D).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calendar_today, color: Color(0xFFFF6B9D)),
                    ),
                    title: Text(
                      'Начало истории 💕',
                      style: TextStyle(
                        fontSize: 16,
                        color: _nightMode ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                    subtitle: Text(
                      '26 октября 2025 года\nДень, когда началась наша сказка 📖',
                      style: TextStyle(
                        fontSize: 14,
                        color: _nightMode ? Colors.white70 : const Color(0xFF666666),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B9D).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.code, color: Color(0xFFFF6B9D)),
                    ),
                    title: Text(
                      'Версия приложения 💫',
                      style: TextStyle(
                        fontSize: 16,
                        color: _nightMode ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                    subtitle: Text(
                      '1.0.0 Любовное издание\nСоздано с любовью для двоих 💑',
                      style: TextStyle(
                        fontSize: 14,
                        color: _nightMode ? Colors.white70 : const Color(0xFF666666),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B9D).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.favorite, color: Color(0xFFFF6B9D)),
                    ),
                    title: Text(
                      'Философия приложения 💭',
                      style: TextStyle(
                        fontSize: 16,
                        color: _nightMode ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                    subtitle: Text(
                      'Наша пара уникальна\nНаша любовь особенная ✨',
                      style: TextStyle(
                        fontSize: 14,
                        color: _nightMode ? Colors.white70 : const Color(0xFF666666),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Кнопка выхода
            Center(
              child: TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('auth', false);
                  if (!mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const BeautifulAuthScreen()),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B6B),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.exit_to_app, size: 18, color: _nightMode ? Colors.white70 : null),
                    const SizedBox(width: 8),
                    Text(
                      'Выйти из аккаунта 💔',
                      style: TextStyle(
                        color: _nightMode ? Colors.white70 : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ================= BEAUTIFUL MESSAGES ================= */
class _BeautifulMessages extends StatefulWidget {
  const _BeautifulMessages();

  @override
  State<_BeautifulMessages> createState() => __BeautifulMessagesState();
}

class __BeautifulMessagesState extends State<_BeautifulMessages> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocus = FocusNode();

  String _role = 'loved';
  bool _isSending = false;
  Stream<QuerySnapshot>? _messageStream;
  bool _nightMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initMessageStream();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _role = prefs.getString('role') ?? 'loved';
          _nightMode = prefs.getBool('night') ?? false;
        });
      }
    } catch (_) {}
  }

  void _initMessageStream() {
    _messageStream = FirebaseFirestore.instance
        .collection('messages')
        .orderBy('time', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      await FirebaseFirestore.instance.collection('messages').add({
        'text': message,
        'author': _role,
        'time': FieldValue.serverTimestamp(),
      });
      _messageController.clear();
      _messageFocus.unfocus();
      
      _scrollToBottom();
    } catch (e) {
      if (kDebugMode) print('Send error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageBubble(DocumentSnapshot doc) {
    final isMe = doc['author'] == _role;
    final timestamp = doc['time'];
    DateTime time;
    
    if (timestamp is Timestamp) {
      time = timestamp.toDate();
    } else {
      time = DateTime.now();
    }
    
    final timeStr = '${time.hour.toString().padLeft(2, '0')}:' +
        '${time.minute.toString().padLeft(2, '0')}';
    
    final messageText = doc['text'];
    final hasLoveEmoji = messageText.contains('любовь') || 
                         messageText.contains('люблю') ||
                         messageText.contains('💖') ||
                         messageText.contains('💕') ||
                         messageText.contains('💝') ||
                         messageText.contains('😍');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isMe ? const Color(0xFFFF6B9D) : const Color(0xFF4A90E2),
              ),
              child: Icon(
                isMe ? Icons.person : Icons.person_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
          
          const SizedBox(width: 8),
          
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: hasLoveEmoji
                        ? _nightMode ? const Color(0xFF2A1A2A) : const Color(0xFFFFF0F8)
                        : (isMe
                            ? _nightMode ? const Color(0xFF2A1A2A) : const Color(0xFFFF6B9D).withOpacity(0.1)
                            : _nightMode ? const Color(0xFF1A2A2A) : const Color(0xFF4A90E2).withOpacity(0.1)),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isMe
                          ? const Radius.circular(16)
                          : const Radius.circular(4),
                      bottomRight: isMe
                          ? const Radius.circular(4)
                          : const Radius.circular(16),
                    ),
                    border: hasLoveEmoji
                        ? Border.all(
                            color: const Color(0xFFFF6B9D).withOpacity(_nightMode ? 0.5 : 0.3),
                            width: 1.5,
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        messageText,
                        style: TextStyle(
                          color: _nightMode ? Colors.white : const Color(0xFF333333),
                          fontSize: 15,
                        ),
                      ),
                      if (hasLoveEmoji) ...[
                        const SizedBox(height: 4),
                        Text(
                          '💖 Любовное послание 💖',
                          style: TextStyle(
                            fontSize: 12,
                            color: _nightMode ? const Color(0xFFFFA8C5) : const Color(0xFFFF6B9D),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 12,
                        color: _nightMode ? Colors.white60 : const Color(0xFF999999),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (isMe) const Text('✅', style: TextStyle(fontSize: 10)),
                    if (!isMe) const Text('👀', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          
          if (isMe)
            const SizedBox(width: 8),
          
          if (isMe)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isMe ? const Color(0xFFFF6B9D) : const Color(0xFF4A90E2),
              ),
              child: Icon(
                isMe ? Icons.person : Icons.person_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Шапка чата с романтичным текстом
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _nightMode ? const Color(0xFF1E1E1E) : Colors.white,
            border: Border(
              bottom: BorderSide(color: _nightMode ? Colors.grey.shade800 : Colors.grey.shade200),
            ),
          ),
          child: Column(
            children: [
              Text(
                '💌 Ваши любовные послания',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _nightMode ? const Color(0xFFFFA8C5) : const Color(0xFFFF6B9D),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Пишите друг другу нежные слова и признания 💕',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: _nightMode ? Colors.white70 : const Color(0xFF666666),
                ),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _messageStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '💔 Ошибка загрузки',
                        style: TextStyle(
                          color: _nightMode ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _initMessageStream,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B9D),
                        ),
                        child: const Text('Попробовать снова 🔄'),
                      ),
                    ],
                  ),
                );
              }

              if (!snapshot.hasData) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B9D)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Загружаем ваши любовные послания... 💖',
                        style: TextStyle(
                          fontSize: 14,
                          color: _nightMode ? Colors.white70 : const Color(0xFF666666),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final messages = snapshot.data!.docs;
              
              if (messages.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 60,
                        color: _nightMode ? const Color(0xFFFFA8C5) : const Color(0xFFFF6B9D),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Здесь пока тихо... 🌙',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _nightMode ? Colors.white : const Color(0xFF333333),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Напиши что-то миленькое! 💝',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _nightMode ? Colors.white70 : const Color(0xFF666666),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          _messageFocus.requestFocus();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B9D),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Написать что-то важное'),
                            SizedBox(width: 8),
                            Text('💝'),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              
              return ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return _buildMessageBubble(messages[index]);
                },
              );
            },
          ),
        ),
        
        // Поле ввода
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _nightMode ? const Color(0xFF1E1E1E) : Colors.white,
            border: Border(
              top: BorderSide(color: _nightMode ? Colors.grey.shade800 : Colors.grey.shade200),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(_nightMode ? 0.05 : 0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickMessageButton('Я люблю тебя! 💖', () {
                      _messageController.text = 'Я люблю тебя! 💖';
                    }),
                    const SizedBox(width: 8),
                    _buildQuickMessageButton('Скучаю по тебе 😔', () {
                      _messageController.text = 'Скучаю по тебе 😔';
                    }),
                    const SizedBox(width: 8),
                    _buildQuickMessageButton('Ты лучшее в моей жизни ✨', () {
                      _messageController.text = 'Ты лучшее в моей жизни ✨';
                    }),
                    const SizedBox(width: 8),
                    _buildQuickMessageButton('Спокойной ночи 😴💕', () {
                      _messageController.text = 'Спокойной ночи, мой любимый 😴💕';
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _nightMode ? const Color(0xFF2A2A2A) : const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: const Color(0xFFFF6B9D).withOpacity(_nightMode ? 0.5 : 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              focusNode: _messageFocus,
                              decoration: InputDecoration(
                                hintText: 'Напиши что-то красивое... 💝',
                                border: InputBorder.none,
                                hintStyle: TextStyle(
                                  color: _nightMode ? Colors.white60 : const Color(0xFF999999),
                                ),
                              ),
                              maxLines: null,
                              onSubmitted: (_) => _sendMessage(),
                              style: TextStyle(
                                fontSize: 15,
                                color: _nightMode ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                          if (_isSending)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFFFF6B9D),
                                  ),
                                ),
                              ),
                            ),
                          IconButton(
                            icon: Icon(
                              Icons.insert_emoticon,
                              color: _nightMode ? const Color(0xFFFFA8C5) : const Color(0xFFFF6B9D),
                            ),
                            onPressed: () {
                              _messageController.text += ' 💖';
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF6B9D), Color(0xFFFFA8C5)],
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: _sendMessage,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickMessageButton(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _nightMode ? const Color(0xFF2A1A2A) : const Color(0xFFFFF0F8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFF6B9D).withOpacity(_nightMode ? 0.5 : 0.3),
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: _nightMode ? const Color(0xFFFFA8C5) : const Color(0xFFFF6B9D),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}