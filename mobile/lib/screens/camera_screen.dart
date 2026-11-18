import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 메인 카메라 화면. 프리뷰와 촬영 UI는 M2(PRD Step 2)에서 구성한다.
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            const Center(child: Text('라익찍스')),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: '설정',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push('/settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
