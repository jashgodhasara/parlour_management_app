import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const IphonePasscodeScreen(),
    );
  }
}

class IphonePasscodeScreen extends StatefulWidget {
  const IphonePasscodeScreen({super.key, this.child, this.passcode = '123456'});

  final Widget? child;
  final String passcode;

  @override
  State<IphonePasscodeScreen> createState() => _IphonePasscodeScreenState();
}

class _IphonePasscodeScreenState extends State<IphonePasscodeScreen> {
  String pin = "";
  bool unlocked = false;
  bool hasError = false;

  void addNumber(String number) {
    if (pin.length < 6) {
      setState(() {
        pin += number;
        hasError = false;
      });

      if (pin.length == 6) {
        Future.delayed(const Duration(milliseconds: 180), () {
          if (!mounted) return;
          if (pin == widget.passcode && widget.child != null) {
            setState(() => unlocked = true);
          } else {
            setState(() {
              pin = "";
              hasError = true;
            });
          }
        });
      }
    }
  }

  void removeNumber() {
    if (pin.isNotEmpty) {
      setState(() {
        pin = pin.substring(0, pin.length - 1);
      });
    }
  }

  Widget buildDot(bool filled) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: filled ? Colors.white : Colors.transparent,
        border: Border.all(color: Colors.white, width: 2),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget numberButton(String number) {
    return GestureDetector(
      onTap: () => addNumber(number),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 32,
              color: Colors.white,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (unlocked && widget.child != null) {
      return _PhoneShell(child: widget.child!);
    }

    final passcodeScreen = Scaffold(
      body: _PasscodeBody(
        pin: pin,
        hasError: hasError,
        buildDot: buildDot,
        numberButton: numberButton,
        removeNumber: removeNumber,
      ),
    );

    if (widget.child == null) {
      return passcodeScreen;
    }

    return _PhoneShell(child: passcodeScreen);
  }
}

class _PasscodeBody extends StatelessWidget {
  const _PasscodeBody({
    required this.pin,
    required this.hasError,
    required this.buildDot,
    required this.numberButton,
    required this.removeNumber,
  });

  final String pin;
  final bool hasError;
  final Widget Function(bool filled) buildDot;
  final Widget Function(String number) numberButton;
  final VoidCallback removeNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xff1c1c1e),
            Color(0xff000000),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 70),
            const Text(
              "Enter Passcode",
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                6,
                (index) => buildDot(index < pin.length),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 22,
              child: Text(
                hasError ? "Wrong passcode" : "",
                style: const TextStyle(
                  color: Color(0xffff6b6b),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      numberButton("1"),
                      numberButton("2"),
                      numberButton("3"),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      numberButton("4"),
                      numberButton("5"),
                      numberButton("6"),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      numberButton("7"),
                      numberButton("8"),
                      numberButton("9"),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const SizedBox(width: 80),
                      numberButton("0"),
                      GestureDetector(
                        onTap: removeNumber,
                        child: const SizedBox(
                          width: 80,
                          height: 80,
                          child: Center(
                            child: Icon(
                              Icons.backspace_outlined,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}

class _PhoneShell extends StatelessWidget {
  const _PhoneShell({required this.child});

  final Widget child;
  static const Size phoneSize = Size(390, 844);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context).copyWith(
      size: phoneSize,
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      viewPadding: const EdgeInsets.only(top: 24, bottom: 10),
      viewInsets: EdgeInsets.zero,
    );

    return Scaffold(
      backgroundColor: const Color(0xff111827),
      body: Center(
        child: Container(
          width: phoneSize.width + 24,
          height: phoneSize.height + 24,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(36),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 36,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: SizedBox(
              width: phoneSize.width,
              height: phoneSize.height,
              child: MediaQuery(data: mediaQuery, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
