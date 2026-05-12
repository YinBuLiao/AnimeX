import 'package:flutter/material.dart';

import 'package:animex_mobile/features/discover/ranking_view.dart';
import 'package:animex_mobile/features/discover/schedule_view.dart';
import 'package:animex_mobile/features/discover/search_view.dart';

class DiscoverTab extends StatelessWidget {
  const DiscoverTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('发现'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '时间表'),
              Tab(text: '排行'),
              Tab(text: '搜索'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ScheduleView(),
            RankingView(),
            SearchView(),
          ],
        ),
      ),
    );
  }
}
