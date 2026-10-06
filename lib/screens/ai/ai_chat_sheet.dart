import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/ai_chat_message.dart';
import '../../models/financial_summary.dart';
import '../../providers/ai_insight_provider.dart';
import '../../theme/mornye_theme.dart';
import '../../widgets/common/flame_mascot.dart';
import '../../widgets/common/mornye_chrome.dart';

/// Bottom sheet for the FIXED-TOPIC finance assistant.
///
/// The user can only ask about their own money (spending, budgets, categories,
/// saving). The backend refuses anything else, so this stays an insight tool
/// rather than a general chatbot.
class AiChatSheet extends StatefulWidget {
  const AiChatSheet({super.key, this.initialQuestion});

  final String? initialQuestion;

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestion != null &&
        widget.initialQuestion!.trim().isNotEmpty) {
      _controller.text = widget.initialQuestion!.trim();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<String> _suggestions(AiInsightProvider provider) {
    final summary = provider.summary;
    final mood = provider.mood;
    final insight = provider.insight;
    final list = <String>[];

    if (insight != null && insight.action.trim().isNotEmpty) {
      list.add(insight.action.trim());
    }
    if (mood != null) {
      if (mood.tone == MoodTone.warn || mood.tone == MoodTone.bad) {
        list.add('Why did my spending go up?');
        list.add('Which category had the highest expense?');
      } else if (mood.tone == MoodTone.good) {
        list.add('How much did I save this month?');
        list.add('Am I on track with my budget?');
      }
    }
    list.add('How much did I spend this month?');
    list.add('How much did I spend this week?');
    list.add('Am I over budget?');
    if (summary?.topCategory != null) {
      list.add('How much did I spend on ${summary!.topCategory}?');
    }
    list.add('Where can I save money?');
    return list.toSet().toList();
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();
    final provider = context.read<AiInsightProvider>();
    await provider.sendChat(text);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = context.glass;
    final provider = context.watch<AiInsightProvider>();
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        decoration: BoxDecoration(
          color: glass.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _handle(theme, glass),
              _header(theme),
              const Divider(height: 1),
              Flexible(
                child: provider.chat.isEmpty
                    ? _emptyState(theme, glass, provider)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        itemCount: provider.chat.length,
                        itemBuilder: (context, index) =>
                            _bubble(theme, provider.chat[index]),
                      ),
              ),
              if (provider.chat.isNotEmpty) _suggestionRow(theme, provider),
              _input(theme, provider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle(ThemeData theme, GlassThemeCompat glass) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: glass.textTertiary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final provider = context.watch<AiInsightProvider>();
    final mood = provider.mood;
    final glass = context.glass;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: <Widget>[
          FlameMascot(
            face: mood?.face ?? MoodFace.calm,
            tone: mood?.tone ?? MoodTone.neutral,
            energy: mood?.energy,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        'Ask Flamey about your money',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (mood != null) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: mood.color(context).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          mood.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: mood.color(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  mood?.message ?? 'Answers use only your own spending data',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: glass.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(
    ThemeData theme,
    GlassThemeCompat glass,
    AiInsightProvider provider,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Try asking:',
            style: theme.textTheme.labelMedium?.copyWith(
              color: glass.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final suggestion in _suggestions(provider))
                MornyeFilterChip(
                  label: suggestion,
                  selected: false,
                  glass: false,
                  tonal: true,
                  onTap: () => _send(suggestion),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestionRow(ThemeData theme, AiInsightProvider provider) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: <Widget>[
          for (final suggestion in _suggestions(provider))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: MornyeFilterChip(
                label: suggestion,
                selected: false,
                glass: false,
                tonal: true,
                onTap: provider.chatSending ? null : () => _send(suggestion),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bubble(ThemeData theme, AiChatMessage message) {
    final isUser = message.fromUser;
    final bg = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.07);
    final fg = isUser
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: message.failed
              ? Border.all(color: const Color(0xffff453a))
              : null,
        ),
        child: message.pending
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  ),
                  const SizedBox(width: 8),
                  Text(message.text, style: TextStyle(color: fg)),
                ],
              )
            : Text(message.text, style: TextStyle(color: fg, height: 1.35)),
      ),
    );
  }

  Widget _input(ThemeData theme, AiInsightProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (value) =>
                  provider.chatSending ? null : _send(value),
              decoration: InputDecoration(
                hintText: 'Ask Flamey about your spending…',
                fillColor: MornyeTheme.controlFill(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: provider.chatSending
                ? null
                : () => _send(_controller.text),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
