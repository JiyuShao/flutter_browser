// Copyright 2020 Lorenzo Pichilli
// Reference https://github.com/pichillilorenzo/flutter_browser_app/blob/master/lib/models/browser_model.dart
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:appleickle_browser/utils/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:appleickle_browser/screens/webview_tab/webview_tab_screen.dart';
import 'webview_model.dart';
import 'search_engine_model.dart';

class BrowserSettingsModel {
  SearchEngineModel searchEngine;
  bool debuggingEnabled;

  BrowserSettingsModel(
      {this.searchEngine = GoogleSearchEngine, this.debuggingEnabled = false});

  BrowserSettingsModel copy() {
    return BrowserSettingsModel(
        searchEngine: searchEngine, debuggingEnabled: debuggingEnabled);
  }

  static BrowserSettingsModel? fromMap(Map<String, dynamic>? map) {
    return map != null
        ? BrowserSettingsModel(
            searchEngine: SearchEngines[map["searchEngineIndex"]],
            debuggingEnabled: map["debuggingEnabled"])
        : null;
  }

  Map<String, dynamic> toMap() {
    return {
      "searchEngineIndex": SearchEngines.indexOf(searchEngine),
      "debuggingEnabled": debuggingEnabled
    };
  }

  Map<String, dynamic> toJson() {
    return toMap();
  }

  @override
  String toString() {
    return toMap().toString();
  }
}

class BrowserModel extends ChangeNotifier {
  final List<WebViewTabScreen> _webViewTabs = [];
  int _currentTabIndex = -1;
  BrowserSettingsModel _settings = BrowserSettingsModel();
  late WebViewModel _currentWebViewModel;

  BrowserModel(WebViewModel? currentWebViewModel) {
    if (currentWebViewModel != null) {
      _currentWebViewModel = currentWebViewModel;
    }
  }

  UnmodifiableListView<WebViewTabScreen> get webViewTabs =>
      UnmodifiableListView(_webViewTabs);

  // 添加新的 tab
  void addNewTab({int? windowId}) {
    addTab(WebViewTabScreen.createEmptyWebViewTabScreen(windowId: windowId));
  }

  // 添加 tab
  void addTab(WebViewTabScreen webViewTab) {
    _webViewTabs.add(webViewTab);
    _currentTabIndex = _webViewTabs.length - 1;
    webViewTab.webViewModel.tabIndex = _currentTabIndex;

    _currentWebViewModel.updateWithValue(webViewTab.webViewModel);
    loggerNoStack.d('添加 WebView Tab $webViewTab');

    notifyListeners();
  }

  // 添加 tab 列表
  void addTabs(List<WebViewTabScreen> webViewTabs) {
    for (var webViewTab in webViewTabs) {
      _webViewTabs.add(webViewTab);
      webViewTab.webViewModel.tabIndex = _webViewTabs.length - 1;
    }
    _currentTabIndex = _webViewTabs.length - 1;
    if (_currentTabIndex >= 0) {
      _currentWebViewModel.updateWithValue(webViewTabs.last.webViewModel);
    }

    notifyListeners();
  }

  void closeTab(int index) {
    _webViewTabs.removeAt(index);
    _currentTabIndex = _webViewTabs.length - 1;

    for (int i = index; i < _webViewTabs.length; i++) {
      _webViewTabs[i].webViewModel.tabIndex = i;
    }

    if (_currentTabIndex >= 0) {
      _currentWebViewModel
          .updateWithValue(_webViewTabs[_currentTabIndex].webViewModel);
    } else {
      _currentWebViewModel.updateWithValue(WebViewModel());
    }

    // 如果关闭当前页面后 tab 页面列表为空的话, 添加新的页面
    if (_webViewTabs.isEmpty) {
      addNewTab();
    } else {
      notifyListeners();
    }
  }

  void showTab(int index) {
    if (_currentTabIndex != index) {
      _currentTabIndex = index;
      _currentWebViewModel
          .updateWithValue(_webViewTabs[_currentTabIndex].webViewModel);

      notifyListeners();
    }
  }

  void closeAllTabs() {
    _webViewTabs.clear();
    _currentTabIndex = -1;
    _currentWebViewModel.updateWithValue(WebViewModel());

    notifyListeners();
  }

  int getTabsLength() => _webViewTabs.length;

  int getCurrentTabIndex() => _currentTabIndex;

  WebViewTabScreen? getCurrentTab() {
    return _currentTabIndex >= 0 ? _webViewTabs[_currentTabIndex] : null;
  }

  BrowserSettingsModel getSettings() {
    return _settings.copy();
  }

  void updateSettings(BrowserSettingsModel settings) {
    _settings = settings;
    notifyListeners();
  }

  void setCurrentWebViewModel(WebViewModel webViewModel) {
    _currentWebViewModel = webViewModel;
  }

  DateTime _lastTrySave = DateTime.now();
  Timer? _timerSave;
  Future<void> save() async {
    _timerSave?.cancel();

    if (DateTime.now().difference(_lastTrySave) >=
        Duration(milliseconds: 400)) {
      _lastTrySave = DateTime.now();
      await flush();
    } else {
      _lastTrySave = DateTime.now();
      _timerSave = Timer(Duration(milliseconds: 500), () {
        save();
      });
    }
  }

  Future<void> flush() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("browser", json.encode(toJson()));
  }

  Future<void> restore() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> browserData;
    try {
      browserData = await json.decode(prefs.getString("browser")!);
    } catch (e) {
      print(e);
      return;
    }

    closeAllTabs();

    // restore 设置数据
    BrowserSettingsModel settings = BrowserSettingsModel.fromMap(
            browserData["settings"]?.cast<String, dynamic>()) ??
        BrowserSettingsModel();

    // restore webViewTabs 数据
    List<Map<String, dynamic>> webViewTabList =
        browserData["webViewTabs"]?.cast<Map<String, dynamic>>() ?? [];
    List<WebViewTabScreen> webViewTabs = webViewTabList
        .map((e) => WebViewTabScreen(
              key: GlobalKey(),
              webViewModel: WebViewModel.fromMap(e)!,
            ))
        .toList();
    // 至少保证存在一个 tab 页面
    if (webViewTabs.isEmpty) {
      webViewTabs = [
        WebViewTabScreen.createEmptyWebViewTabScreen(),
      ];
    }
    webViewTabs.sort(
        (a, b) => a.webViewModel.tabIndex!.compareTo(b.webViewModel.tabIndex!));

    updateSettings(settings);
    addTabs(webViewTabs);

    int currentTabIndex = browserData["currentTabIndex"] ?? _currentTabIndex;
    currentTabIndex = min(currentTabIndex, _webViewTabs.length - 1);

    if (currentTabIndex >= 0) showTab(currentTabIndex);
  }

  Map<String, dynamic> toMap() {
    return {
      "webViewTabs": _webViewTabs.map((e) => e.webViewModel.toMap()).toList(),
      "currentTabIndex": _currentTabIndex,
      "settings": _settings.toMap(),
      "currentWebViewModel": _currentWebViewModel.toMap(),
    };
  }

  Map<String, dynamic> toJson() {
    return toMap();
  }

  @override
  String toString() {
    return toMap().toString();
  }
}
