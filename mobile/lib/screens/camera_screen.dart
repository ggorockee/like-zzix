import 'package:flutter/material.dart';

/// 메인 카메라 화면. 프리뷰와 촬영 UI는 M2(PRD Step 2)에서 구성한다.
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: Text('라익찍스')),
    );
  }
}
