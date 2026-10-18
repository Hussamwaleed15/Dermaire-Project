import 'package:flutter/material.dart';

import 'message_timeline.dart';
import 'messaging_models.dart';

/// Earlier server-ordered rows grow above a stable sliver origin. No estimated
/// extent correction or cached message payload is needed when rows wrap.
class AnchoredConversation extends StatefulWidget {
  const AnchoredConversation({
    super.key,
    required this.header,
    required this.footer,
    required this.messages,
    required this.owner,
    required this.role,
    required this.peerRead,
  });
  final List<Widget> header, footer;
  final List<CareMessage> messages;
  final String owner, role;
  final int peerRead;

  @override
  State<AnchoredConversation> createState() => _AnchoredConversationState();
}

class _AnchoredConversationState extends State<AnchoredConversation> {
  final scroll = ScrollController(keepScrollOffset: false);
  static const center = ValueKey('conversationOrigin');
  int? origin;
  bool positioned = false;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (origin == null && widget.messages.isNotEmpty) {
      origin = widget.messages.first.sequence;
      positioned = false;
    }
    if (!positioned) {
      positioned = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(scroll.position.minScrollExtent);
        }
      });
    }
    final split = origin == null
        ? 0
        : widget.messages.indexWhere((m) => m.sequence >= origin!);
    final boundary = split < 0 ? widget.messages.length : split;
    Widget row(int index) => CareMessageRow(
      key: ValueKey(widget.messages[index].id),
      message: widget.messages[index],
      owner: widget.owner,
      role: widget.role,
      peerRead: widget.peerRead,
      // Preserve the origin's geometry even if an earlier same-day row arrives.
      startsDay:
          index == 0 ||
          index == boundary ||
          messageUtcDay(widget.messages[index - 1].createdAt) !=
              messageUtcDay(widget.messages[index].createdAt),
    );
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: CustomScrollView(
          key: const ValueKey('conversationScroll'),
          controller: scroll,
          center: center,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.header,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: boundary,
                itemBuilder: (_, i) => row(boundary - 1 - i),
              ),
            ),
            SliverPadding(
              key: center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.builder(
                itemCount: widget.messages.length - boundary,
                itemBuilder: (_, i) => row(boundary + i),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.footer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
