import 'package:flutter/material.dart';

import '../app.dart';
import 'dictation_page.dart';
import 'draw_page.dart';
import 'flower_page.dart';
import 'settings_page.dart';
import 'roster_page.dart';

/// 左侧导航 + 右侧内容的主框架（卡通配色）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<(String, String, String)> _destinations = [
    ('👦', '👦', '名单'),
    ('🌸', '🌸', '小红花'),
    ('🎲', '🎲', '抽签'),
    ('🔊', '🔊', '听写'),
    ('⚙️', '⚙️', '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const RosterPage(),
      const FlowerPage(),
      const DrawPage(),
      const DictationPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            groupAlignment: -1.0,
            backgroundColor: ClassManagerApp.yellow,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Column(
                children: [
                  Text('🏫', style: TextStyle(fontSize: 34)),
                  SizedBox(height: 4),
                  Text(
                    '班级乐园',
                    style: TextStyle(
                      fontFamily: 'KuaiLe',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: ClassManagerApp.ink,
                    ),
                  ),
                ],
              ),
            ),
            indicatorColor: Colors.white,
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Text(d.$1, style: const TextStyle(fontSize: 22)),
                  selectedIcon: Text(d.$2, style: const TextStyle(fontSize: 26)),
                  label: Text(
                    d.$3,
                    style: const TextStyle(
                      fontFamily: 'KuaiLe',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: ClassManagerApp.ink,
                    ),
                  ),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 3, color: ClassManagerApp.ink),
          Expanded(child: pages[_index]),
        ],
      ),
    );
  }
}
