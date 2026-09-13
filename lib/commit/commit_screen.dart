import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../ui/workbench_action_accents.dart';
import 'commit_composer.dart';
import 'commit_diff_pane.dart';
import 'git_commit_notice.dart';
import 'git_working_tree.dart';
import 'uncommitted_change_counts.dart';
import 'uncommitted_changes_cache.dart';
import 'uncommitted_file_diff.dart';

class const CommitScreen({
  required final String gitRoot,
  required final String repoName,
}) extends StatefulWidget {
  @override
  State<CommitScreen> createState() => _CommitScreenState();
}

class _CommitScreenState() extends State<CommitScreen> {
  final _messageController = TextEditingController();
  final _notices = <GitCommitNotice>[];
  List<UncommittedFileDiff> _files = const [];
  UncommittedChangeCounts _counts = UncommittedChangeCounts.clean;
  var _hasPushRemote = false;
  var _loading = true;
  var _running = false;
  var _commitCompleted = false;
  var _succeeded = false;
  String? _errorMessage;

  GitWorkingTree get _workingTree => GitWorkingTree.at(widget.gitRoot);

  @override
  void initState() {
    super.initState();
    unawaited(_loadWorkingTree());
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadWorkingTree() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final files = await _workingTree.fileDiffs();
      final counts = await _workingTree.changeCounts();
      final hasPushRemote = await _workingTree.hasPushRemote;
      if (!mounted) return;
      setState(() {
        _files = files;
        _counts = counts;
        _hasPushRemote = hasPushRemote;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_succeeded) {
      Navigator.of(context).pop();
      return;
    }
    if (_running) return;
    setState(() => _running = true);
    try {
      if (_commitCompleted) {
        await _workingTree.pushToRemote(
          onNotice: _appendNotice,
          afterCommit: true,
        );
      } else {
        await _workingTree.commitAll(
          message: _messageController.text,
          push: _hasPushRemote,
          onNotice: _appendNotice,
        );
        _commitCompleted = true;
      }
      if (!mounted) return;
      await UncommittedChangesCache.instance.refresh(widget.gitRoot);
      if (!mounted) return;
      setState(() {
        _running = false;
        _succeeded = true;
        _showCommittedWorkingTree();
      });
    } on GitWorkingTreeFailed catch (error) {
      if (!mounted) return;
      _appendNotice(GitCommitNotice.danger(error.message));
      setState(() {
        _running = false;
        if (error.commitCompleted) {
          _commitCompleted = true;
          _showCommittedWorkingTree();
        }
      });
      await UncommittedChangesCache.instance.refresh(widget.gitRoot);
    } catch (error) {
      if (!mounted) return;
      _appendNotice(GitCommitNotice.danger(error.toString()));
      setState(() => _running = false);
    }
  }

  void _appendNotice(GitCommitNotice notice) {
    if (!mounted) return;
    setState(() => _notices.add(notice));
  }

  void _showCommittedWorkingTree() {
    _files = const [];
    _counts = UncommittedChangeCounts.clean;
  }

  String get _actionLabel {
    if (_succeeded) return 'Done';
    if (_running) {
      if (_commitCompleted) return 'Pushing';
      return _hasPushRemote ? 'Commit & push' : 'Commit';
    }
    if (_commitCompleted && _hasPushRemote) return 'Push';
    return _hasPushRemote ? 'Commit & push' : 'Commit';
  }

  bool get _actionEnabled {
    if (_running) return false;
    if (_succeeded) return true;
    if (_commitCompleted && _hasPushRemote) return true;
    if (_counts.isClean) return false;
    return _messageController.text.trim().isNotEmpty;
  }

  bool get _messageEnabled => !_running && !_succeeded && !_commitCompleted;

  String get _headerSubtitle {
    if (_succeeded) {
      return _hasPushRemote ? 'Committed and pushed' : 'Committed';
    }
    if (_loading) return 'Loading diffs…';
    return _counts.caption;
  }

  @override
  Widget build(BuildContext context) {
    return EScaffoldShell(
      contentMaxWidth: double.infinity,
      appBar: EAppHeader(
        eyebrow: 'COMMIT',
        title: widget.repoName,
        subtitle: _headerSubtitle,
        accent: WorkbenchActionAccents.commit,
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading && _files.isEmpty && _errorMessage == null) {
      return const ELoadingState(message: 'Reading uncommitted changes…');
    }
    if (_errorMessage != null && _files.isEmpty) {
      return EEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Could not read changes',
        message: _errorMessage!,
        action: FilledButton(
          onPressed: () => unawaited(_loadWorkingTree()),
          child: const Text('Retry'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: CommitDiffPane(files: _files)),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ELayout.spaceLg,
            0,
            ELayout.spaceLg,
            ELayout.spaceLg,
          ),
          child: CommitComposer(
            messageController: _messageController,
            notices: _notices,
            actionLabel: _actionLabel,
            actionEnabled: _actionEnabled,
            messageEnabled: _messageEnabled,
            running: _running,
            onSubmit: _actionEnabled ? () => unawaited(_submit()) : null,
            onMessageChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }
}
