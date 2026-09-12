import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart' show ouvrirRoute;
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/auth/auth_state.dart';
import '../../core/db/app_database.dart';
import '../dashboard/dashboard_page.dart' show tousArticlesProvider;
import '../ventes/ventes_page.dart' show tousClientsProvider;
import 'ai_client.dart';
import 'ai_config.dart';
import 'ai_actions.dart';
import 'ai_contexte.dart';
import 'ai_outils.dart';
import 'action_executeur.dart';
import 'action_sheet.dart';
import 'voix.dart';

// --- Modèle de message local ---
class ChatMessage {
  final String role; // 'user' ou 'assistant'
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

// --- Modèle de Session de Discussion ---
class ChatSession {
  final String id;
  final String title;
  final DateTime date;
  final List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.date,
    required this.messages,
  });

  ChatSession copyWith({
    String? title,
    List<ChatMessage>? messages,
  }) {
    return ChatSession(
      id: id,
      title: title ?? this.title,
      date: date,
      messages: messages ?? this.messages,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Conversation',
        date: DateTime.parse(json['date'] as String),
        messages: (json['messages'] as List<dynamic>?)
                ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

// --- Management des Sessions d'historique dans la table KV ---
typedef ChatSessionsState = ({List<ChatSession> sessions, String? activeId});

final chatSessionsProvider =
    StateNotifierProvider<ChatSessionsNotifier, ChatSessionsState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ChatSessionsNotifier(db);
});

class ChatSessionsNotifier extends StateNotifier<ChatSessionsState> {
  final AppDatabase _db;

  ChatSessionsNotifier(this._db) : super((sessions: [], activeId: null)) {
    _load();
  }

  Future<void> _load() async {
    final row = await (_db.select(_db.kv)
          ..where((k) => k.cle.equals('assistant_chat_sessions'))
          ..limit(1))
        .getSingleOrNull();

    if (row != null) {
      try {
        final List<dynamic> list = jsonDecode(row.valeur);
        final loadedSessions =
            list.map((e) => ChatSession.fromJson(e)).toList();
        if (loadedSessions.isNotEmpty) {
          state = (
            sessions: loadedSessions,
            activeId: loadedSessions.first.id,
          );
          return;
        }
      } catch (_) {}
    }
    _createNewSession();
  }

  Future<void> _save() async {
    final jsonStr =
        jsonEncode(state.sessions.map((s) => s.toJson()).toList());
    await _db.into(_db.kv).insertOnConflictUpdate(
          KvCompanion(
            cle: const Value('assistant_chat_sessions'),
            valeur: Value(jsonStr),
          ),
        );
  }

  void createNewSession() {
    _createNewSession();
  }

  void _createNewSession() {
    final now = DateTime.now();
    final newSession = ChatSession(
      id: now.millisecondsSinceEpoch.toString(),
      title: 'Nouvelle conversation',
      date: now,
      messages: [],
    );

    state = (
      sessions: [newSession, ...state.sessions],
      activeId: newSession.id,
    );
    _save();
  }

  void selectSession(String id) {
    state = (sessions: state.sessions, activeId: id);
  }

  Future<void> addMessageToActiveSession(ChatMessage message) async {
    final activeId = state.activeId;
    if (activeId == null) return;

    final updatedSessions = state.sessions.map((s) {
      if (s.id == activeId) {
        final newMessages = [...s.messages, message];
        String newTitle = s.title;

        // Auto-générer le titre si c'est le premier message utilisateur
        if (s.messages.isEmpty && message.role == 'user') {
          newTitle = message.content.length > 28
              ? '${message.content.substring(0, 28)}…'
              : message.content;
        }

        return s.copyWith(title: newTitle, messages: newMessages);
      }
      return s;
    }).toList();

    state = (sessions: updatedSessions, activeId: activeId);
    await _save();
  }

  Future<void> renameSession(String id, String newTitle) async {
    if (newTitle.trim().isEmpty) return;
    final updated = state.sessions.map((s) {
      if (s.id == id) {
        return s.copyWith(title: newTitle.trim());
      }
      return s;
    }).toList();
    state = (sessions: updated, activeId: state.activeId);
    await _save();
  }

  Future<void> clearActiveSessionMessages() async {
    final activeId = state.activeId;
    if (activeId == null) return;
    final updated = state.sessions.map((s) {
      if (s.id == activeId) {
        return s.copyWith(title: 'Nouvelle conversation', messages: []);
      }
      return s;
    }).toList();
    state = (sessions: updated, activeId: activeId);
    await _save();
  }

  Future<void> deleteSession(String id) async {
    final updatedSessions = state.sessions.where((s) => s.id != id).toList();
    String? newActiveId = state.activeId;

    if (newActiveId == id) {
      newActiveId =
          updatedSessions.isNotEmpty ? updatedSessions.first.id : null;
    }

    state = (sessions: updatedSessions, activeId: newActiveId);
    if (updatedSessions.isEmpty) {
      _createNewSession();
    } else {
      await _save();
    }
  }

  Future<void> clearAllSessions() async {
    state = (sessions: [], activeId: null);
    _createNewSession();
  }
}

// --- État de réflexion IA ---
final isThinkingProvider = StateProvider<bool>((ref) => false);

// --- Fonction utilitaire de copie dans le presse-papier ---
void _copyToClipboard(BuildContext context, String text,
    {String label = 'Message'}) {
  if (text.isEmpty) return;
  Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.lightImpact();
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$label copié dans le presse-papier !',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ),
        ],
      ),
      backgroundColor: CouleursMetier.clair.succes,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(Espace.page),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.md)),
      duration: const Duration(seconds: 2),
    ),
  );
}

// --- Page principale de l'Assistant IA ---
class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  /// Étape en cours pendant que le modèle interroge le magasin.
  String? _etape;

  /// Indicateur d'affichage du bouton de défilement vers le bas
  bool _showScrollToBottom = false;

  /// Retenu dès l'ouverture : `ref` n'est plus consultable une fois la page
  /// démontée, et c'est précisément là qu'il faut faire taire la lecture.
  late final VoixNotifier _voix;

  @override
  void initState() {
    super.initState();
    _voix = ref.read(voixProvider.notifier);
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final showBtn = (maxScroll - currentScroll) > 150;
    if (showBtn != _showScrollToBottom) {
      setState(() => _showScrollToBottom = showBtn);
    }
  }

  @override
  void dispose() {
    // Quitter la page doit couper la voix : sans cela, elle continue de lire
    // par-dessus l'écran suivant.
    _voix.arreter();
    _scrollController.removeListener(_scrollListener);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Le mode vocal a besoin d'une clé Gemini, quel que soit le fournisseur
  /// choisi pour le texte : c'est lui qui porte la voix.
  void _ouvrirVocal(BuildContext context) {
    final cfg = ref.read(configIAProvider);
    final cleGemini = (cfg.cles[FournisseurIA.gemini] ?? '').trim();
    if (cleGemini.isEmpty) {
      _showError(
          'Le mode vocal fonctionne avec Gemini Live : renseignez une clé '
          'Gemini dans Paramètres → Assistant IA, même si vous utilisez Claude '
          'pour le texte.');
      return;
    }
    context.push('/assistant/vocal');
  }

  void _retourSecurise(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/accueil');
    }
  }

  Future<void> _sendMessage([String? textOverride]) async {
    final text = textOverride ?? _controller.text.trim();
    if (text.isEmpty) return;

    final cfg = ref.read(configIAProvider);
    if (!cfg.utilisable) {
      _showError(
          'L\'assistant n\'a pas encore de clé API. Ouvrez Paramètres → Assistant IA '
          'pour en renseigner une (${cfg.info.nom} : ${cfg.info.aideCle}).');
      return;
    }

    final userMsg = ChatMessage(
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );
    final notifier = ref.read(chatSessionsProvider.notifier);
    await notifier.addMessageToActiveSession(userMsg);

    if (textOverride == null) {
      _controller.clear();
    }

    ref.read(isThinkingProvider.notifier).state = true;
    _scrollToBottom();

    try {
      final systeme = ref.read(contexteIAProvider);
      final donnees = ref.read(donneesMagasinProvider);

      final sessionsState = ref.read(chatSessionsProvider);
      final session = sessionsState.sessions
          .where((s) => s.id == sessionsState.activeId)
          .firstOrNull;

      final historique = (session?.messages ?? const <ChatMessage>[]);
      final tours = [
        for (final m in historique.length > 12
            ? historique.sublist(historique.length - 12)
            : historique)
          TourIA(m.role, m.content),
      ];

      final reponse = await repondreAvecOutils(
        ref.read(clientIAProvider),
        cfg,
        systeme,
        tours,
        donnees,
        surEtape: (etape) {
          if (mounted) setState(() => _etape = etape);
        },
      );

      final trace = reponse.trace.isEmpty
          ? ''
          : '\n\n_Consulté : ${reponse.trace.join(' · ')}_';

      // Le bloc d'action est retiré du texte : il n'a rien à faire sous les
      // yeux du commerçant, c'est la fiche qui le lui présente en français.
      final extrait = extraireActions(reponse.texte);
      final compte = ref.read(authStateProvider).value?.user;

      // Une action que ce compte n'a pas le droit de faire ne doit même pas
      // ouvrir de fiche : proposer un geste pour le refuser ensuite est une
      // promesse qu'on ne tient pas. On la retire ici et on dit pourquoi —
      // sans quoi le refus ressemblerait à une panne.
      final permises = <AppelAction>[];
      final refus = <String>[];
      for (final a in extrait.actions) {
        final v = verifierAction(a.type, a.params, compte);
        if (v.ok) {
          permises.add(a);
        } else {
          refus.add('⛔ **${a.libelle}** — ${v.motif}');
        }
      }

      final noteRefus = refus.isEmpty ? '' : '\n\n---\n${refus.join('\n')}';

      final reponseMsg = ChatMessage(
        role: 'assistant',
        content: extrait.texte + noteRefus + trace,
        timestamp: DateTime.now(),
      );
      await notifier.addMessageToActiveSession(reponseMsg);

      if (permises.isNotEmpty && mounted) {
        unawaited(_proposerActions(permises));
      }

      // Seules les vraies réponses sont lues. Entendre « Quota atteint sur
      // cette clé » énoncé à voix haute au milieu du magasin n'apporte rien.
      final voix = ref.read(voixProvider);
      if (voix.config.active && voix.config.lectureAuto) {
        unawaited(ref
            .read(voixProvider.notifier)
            .parler(_idVocal(reponseMsg), reponseMsg.content));
      }
    } on ErreurIA catch (e) {
      await notifier.addMessageToActiveSession(ChatMessage(
        role: 'assistant',
        content: switch (e.code) {
          CodeErreurIA.pasDeCle =>
            'Aucune clé API n\'est enregistrée. Ouvrez Paramètres → Assistant IA.',
          CodeErreurIA.authentification =>
            'La clé API est refusée par ${cfg.info.nom}. Vérifiez-la dans les paramètres.',
          CodeErreurIA.quota =>
            'Quota atteint sur cette clé. Patientez quelques minutes, ou ajoutez '
                'une seconde clé séparée par une virgule dans les paramètres.',
          CodeErreurIA.reseau =>
            'Assistant indisponible hors ligne. Le reste de l\'application, lui, '
                'continue de fonctionner sans réseau.',
          CodeErreurIA.api => e.message,
        },
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      await notifier.addMessageToActiveSession(ChatMessage(
        role: 'assistant',
        content: 'Erreur inattendue : $e',
        timestamp: DateTime.now(),
      ));
    } finally {
      if (mounted) setState(() => _etape = null);
      ref.read(isThinkingProvider.notifier).state = false;
      _scrollToBottom();
    }
  }

  /// Ouvre la fiche, puis exécute ce qui a été confirmé.
  ///
  /// Rien n'est écrit avant l'appui : la fiche rend `null` à l'annulation, et
  /// l'exécuteur revérifie de toute façon les droits — la fiche n'est qu'un
  /// affichage, elle n'autorise rien par elle-même.
  Future<void> _proposerActions(List<AppelAction> actions) async {
    final contexte = ContexteResume(
      articles: ref.read(tousArticlesProvider).valueOrNull ?? const [],
      clients: ref.read(tousClientsProvider).valueOrNull ?? const [],
    );
    final compte = ref.read(authStateProvider).value?.user;

    final confirmees = await ouvrirFicheActions(
      context,
      actions: actions,
      contexte: contexte,
      manquantsDe: (a) {
        final v = verifierAction(a.type, a.params, compte);
        return v.ok ? v.manquants : const [];
      },
    );
    if (confirmees == null || !mounted) return;

    final executeur = ref.read(executeurActionsProvider);
    final faites = <String>[];
    String? echec;
    String? pageAOuvrir;

    for (final a in confirmees) {
      try {
        final r = await executeur.executer(a);
        faites.add(r.libelle);
        pageAOuvrir ??= r.page;
      } on EchecAction catch (e) {
        echec = e.message;
        break;
      } catch (e) {
        echec = 'Erreur inattendue : $e';
        break;
      }
    }

    // S'arrêter au premier échec est volontaire : les actions enchaînées se
    // supposent l'une l'autre, et poursuivre après un refus enregistrerait la
    // suite d'une opération dont le début n'a pas eu lieu.
    final lignes = <String>[];
    if (faites.isNotEmpty) {
      lignes.add(faites.length == 1
          ? '✅ **Action enregistrée :**'
          : '✅ **${faites.length} actions enregistrées :**');
      lignes.addAll(faites.map((f) => '- $f'));
    }
    if (echec != null) {
      if (faites.isNotEmpty) lignes.add('');
      lignes.add('❌ **Interrompu :** $echec');
      final restantes = confirmees.length - faites.length - 1;
      if (restantes > 0) {
        lignes.add('$restantes action·s suivante·s n\'ont pas été appliquées.');
      }
    }

    if (lignes.isNotEmpty) {
      await ref.read(chatSessionsProvider.notifier).addMessageToActiveSession(
            ChatMessage(
              role: 'assistant',
              content: lignes.join('\n'),
              timestamp: DateTime.now(),
            ),
          );
      _scrollToBottom();
    }

    if (pageAOuvrir != null && pageAOuvrir.isNotEmpty && mounted) {
      final chemin = pageAOuvrir == 'dashboard' ? 'accueil' : pageAOuvrir;
      ouvrirRoute(context, chemin);
    }
  }

  void _regenererDerniereReponse(List<ChatMessage> messages) {
    if (messages.isEmpty) return;
    // Trouver la dernière question de l'utilisateur
    final lastUserMsgIndex =
        messages.lastIndexWhere((m) => m.role == 'user');
    if (lastUserMsgIndex != -1) {
      final userText = messages[lastUserMsgIndex].content;
      _sendMessage(userText);
    }
  }

  void _showError(String message) {
    final errorMsg = ChatMessage(
      role: 'assistant',
      content: message,
      timestamp: DateTime.now(),
    );
    ref.read(chatSessionsProvider.notifier).addMessageToActiveSession(errorMsg);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duree.moyenne,
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _renommerSession(
      BuildContext context, String sessionId, String currentTitle) {
    final txtController = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer la discussion'),
        content: TextField(
          controller: txtController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Titre de la conversation',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(chatSessionsProvider.notifier)
                  .renameSession(sessionId, txtController.text);
              Navigator.pop(ctx);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _effacerSession(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Effacer la discussion'),
        content: const Text(
          'Voulez-vous vraiment effacer tous les messages de cette conversation ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () {
              ref
                  .read(chatSessionsProvider.notifier)
                  .clearActiveSessionMessages();
              Navigator.pop(ctx);
            },
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
  }

  void _ouvrirHistorique(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HistoriqueSessionsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sessionsState = ref.watch(chatSessionsProvider);
    final cfg = ref.watch(configIAProvider);

    final activeSession = sessionsState.sessions.firstWhere(
      (s) => s.id == sessionsState.activeId,
      orElse: () => ChatSession(
          id: '', title: 'Assistant IA', date: DateTime.now(), messages: []),
    );
    final messages = activeSession.messages;
    final isThinking = ref.watch(isThinkingProvider);

    final providerInfo = kFournisseurs[cfg.fournisseur];
    final modelName = providerInfo?.modeles
            .firstWhere((m) => m.id == cfg.modele,
                orElse: () => ModeleIA(cfg.modele, cfg.modele))
            .libelle ??
        cfg.modele;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _retourSecurise(context);
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: Espace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Assistant IA',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: cfg.utilisable
                                ? CouleursMetier.clair.succes
                                : scheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      activeSession.title.isNotEmpty &&
                              activeSession.title != 'Nouvelle conversation'
                          ? activeSession.title
                          : '${providerInfo?.nom ?? "IA"} • $modelName',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _retourSecurise(context),
          ),
          actions: [
            // Couper la voix doit rester à portée de pouce, sans chercher
            // quelle bulle parle : avec la lecture automatique, elle démarre
            // sans qu'on l'ait demandé, et c'est là qu'on veut l'arrêter vite.
            if (ref.watch(voixProvider).enLecture != null)
              IconButton(
                icon: const Icon(Icons.volume_off_rounded),
                color: scheme.error,
                onPressed: () => ref.read(voixProvider.notifier).arreter(),
                tooltip: 'Arrêter la lecture',
              ),
            IconButton(
              icon: const Icon(Icons.graphic_eq_rounded),
              onPressed: () => _ouvrirVocal(context),
              tooltip: 'Mode vocal',
            ),
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: () =>
                  ref.read(chatSessionsProvider.notifier).createNewSession(),
              tooltip: 'Nouvelle conversation',
            ),
            IconButton(
              icon: const Icon(Icons.history_rounded),
              onPressed: () => _ouvrirHistorique(context),
              tooltip: 'Historique des discussions',
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              tooltip: 'Options',
              onSelected: (val) {
                if (val == 'renommer' && activeSession.id.isNotEmpty) {
                  _renommerSession(
                      context, activeSession.id, activeSession.title);
                } else if (val == 'effacer') {
                  _effacerSession(context);
                } else if (val == 'parametres') {
                  context.push('/parametres');
                }
              },
              itemBuilder: (context) => [
                if (messages.isNotEmpty) ...[
                  const PopupMenuItem(
                    value: 'renommer',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Renommer'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'effacer',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Effacer les messages'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                ],
                const PopupMenuItem(
                  value: 'parametres',
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Paramètres Assistant'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Zone de conversation ou d'accueil
              Expanded(
                child: Stack(
                  children: [
                    messages.isEmpty
                        ? _WelcomeSection(
                            config: cfg,
                            onVocal: () => _ouvrirVocal(context),
                            onSelectPrompt: (prompt) {
                              _controller.text = prompt;
                              _sendMessage();
                            },
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: Espace.page,
                              vertical: Espace.sm,
                            ),
                            itemCount: messages.length + (isThinking ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index < messages.length) {
                                final isLastAssistant = index ==
                                        messages.length - 1 &&
                                    messages[index].role == 'assistant';
                                return _MessageBubble(
                                  message: messages[index],
                                  isLastAssistantMessage: isLastAssistant,
                                  onRegenerate: () =>
                                      _regenererDerniereReponse(messages),
                                );
                              }
                              return _IndicateurReflexion(etape: _etape);
                            },
                          ),

                    // Bouton de défilement vers le bas
                    if (_showScrollToBottom)
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: FloatingActionButton.small(
                          onPressed: _scrollToBottom,
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.primary,
                          elevation: 3,
                          tooltip: 'Aller au bas de la discussion',
                          child: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Barre de saisie ──
              // Une pilule ; à droite, le bouton vocal quand le champ est
              // vide, le bouton d'envoi dès qu'on écrit.
              Container(
                padding: const EdgeInsets.fromLTRB(
                    Espace.md, Espace.sm, Espace.md, Espace.md),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(Rayon.xl),
                        ),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                          decoration: InputDecoration(
                            hintText: 'Demandez-moi quelque chose…',
                            hintStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 13,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Espace.sm),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) {
                        final aDuTexte = value.text.trim().isNotEmpty;
                        return AnimatedSwitcher(
                          duration: Duree.rapide,
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: anim,
                            child: child,
                          ),
                          child: aDuTexte
                              ? _BoutonRond(
                                  key: const ValueKey('envoyer'),
                                  icone: Icons.arrow_upward_rounded,
                                  actif: !isThinking,
                                  onTap: isThinking ? null : _sendMessage,
                                  tooltip: 'Envoyer',
                                )
                              : _BoutonRond(
                                  key: const ValueKey('vocal'),
                                  icone: Icons.graphic_eq_rounded,
                                  actif: true,
                                  onTap: () => _ouvrirVocal(context),
                                  tooltip: 'Mode vocal',
                                ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le bouton rond à droite du champ : envoi ou vocal.
class _BoutonRond extends StatelessWidget {
  final IconData icone;
  final bool actif;
  final VoidCallback? onTap;
  final String tooltip;

  const _BoutonRond({
    super.key,
    required this.icone,
    required this.actif,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: actif
              ? LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: actif ? null : scheme.surfaceContainerHigh,
          boxShadow: actif
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Icon(
              icone,
              color: actif
                  ? Colors.white
                  : scheme.onSurfaceVariant.withValues(alpha: 0.5),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

/// « L'assistant réfléchit… » — trois points qui ondulent, et l'outil en
/// cours quand il y en a un.
class _IndicateurReflexion extends StatefulWidget {
  final String? etape;
  const _IndicateurReflexion({required this.etape});

  @override
  State<_IndicateurReflexion> createState() => _IndicateurReflexionState();
}

class _IndicateurReflexionState extends State<_IndicateurReflexion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: Espace.xs, bottom: Espace.sm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final t = ((_c.value - i * 0.18) % 1.0);
                  final y = -4 * math.sin(math.pi * t.clamp(0.0, 0.5) * 2);
                  return Transform.translate(
                    offset: Offset(0, y),
                    child: Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.5 + 0.5 * (1 - t)),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (widget.etape != null) ...[
              const SizedBox(width: Espace.sm),
              Flexible(
                child: Text(
                  widget.etape!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- Section de Bienvenue & Suggestions ---
class _WelcomeSection extends StatelessWidget {
  final ValueChanged<String> onSelectPrompt;
  final VoidCallback onVocal;
  final ConfigIA config;

  const _WelcomeSection({
    required this.onSelectPrompt,
    required this.onVocal,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final providerInfo = kFournisseurs[config.fournisseur];
    final modelName = providerInfo?.modeles
            .firstWhere((m) => m.id == config.modele,
                orElse: () => ModeleIA(config.modele, config.modele))
            .libelle ??
        config.modele;

    final suggestions = [
      (
        icone: Icons.trending_up_rounded,
        titre: 'Chiffre du mois',
        texte: 'Quel est mon chiffre d\'affaires ce mois-ci ?',
      ),
      (
        icone: Icons.inventory_2_rounded,
        titre: 'Ruptures',
        texte: 'Quels articles sont bientôt en rupture ?',
      ),
      (
        icone: Icons.account_balance_wallet_rounded,
        titre: 'Créances',
        texte: 'Quels clients ont des créances impayées ?',
      ),
      (
        icone: Icons.star_rounded,
        titre: 'Meilleures ventes',
        texte: 'Quelles sont mes meilleures ventes ?',
      ),
      (
        icone: Icons.payments_rounded,
        titre: 'Bénéfice',
        texte: 'Est-ce que je gagne de l\'argent ce mois-ci ?',
      ),
      (
        icone: Icons.summarize_rounded,
        titre: 'Rapport',
        texte: 'Rapport rapide du magasin',
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          Espace.page, Espace.lg, Espace.page, Espace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Carte d'accueil ──
          Container(
            padding: const EdgeInsets.all(Espace.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Rayon.xl),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary,
                  Color.lerp(scheme.primary, scheme.tertiary, 0.7)!,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.30),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(Rayon.md),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bonjour 👋',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            '${providerInfo?.nom ?? "IA"} · $modelName',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Espace.md),
                Text(
                  'Je connais vos ventes, votre stock, vos clients et votre '
                  'trésorerie. Posez-moi une question, ou parlez-moi.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: Espace.lg),
                // Le bouton vocal, en évidence : c'est la nouveauté, et c'est
                // le geste naturel au comptoir, les mains prises.
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Rayon.pilule),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onVocal,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 13),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.graphic_eq_rounded,
                              color: scheme.primary, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Parler à l\'assistant',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (!config.utilisable) ...[
            const SizedBox(height: Espace.md),
            Container(
              padding: const EdgeInsets.all(Espace.md),
              decoration: BoxDecoration(
                color: context.metier.alerteFond,
                borderRadius: BorderRadius.circular(Rayon.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.key_off_rounded, color: context.metier.alerte),
                  const SizedBox(width: Espace.sm),
                  Expanded(
                    child: Text(
                      'Aucune clé API : l\'assistant ne peut pas répondre. '
                      'Paramètres → Assistant IA.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: Espace.xl),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: Espace.sm),
            child: Text(
              'POUR COMMENCER',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // Hauteur explicite plutôt qu'un ratio : avec une police système
            // agrandie, le ratio faisait déborder le texte de la tuile.
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: Espace.sm,
              crossAxisSpacing: Espace.sm,
              mainAxisExtent: 136,
            ),
            itemCount: suggestions.length,
            itemBuilder: (context, i) {
              final s = suggestions[i];
              return Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Rayon.lg),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelectPrompt(s.texte),
                  child: Padding(
                    padding: const EdgeInsets.all(Espace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(Rayon.sm),
                          ),
                          child: Icon(s.icone, size: 18, color: scheme.primary),
                        ),
                        const Spacer(),
                        Text(
                          s.titre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Flexible(
                          child: Text(
                            s.texte,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// --- Bulle de message stylisée avec Copie & Actions ---
class _MessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isLastAssistantMessage;
  final VoidCallback? onRegenerate;

  const _MessageBubble({
    required this.message,
    this.isLastAssistantMessage = false,
    this.onRegenerate,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _copied = false;

  void _handleCopy(BuildContext context, String label) {
    _copyToClipboard(context, widget.message.content, label: label);
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  void _handleShare(String text) {
    Share.share(text, subject: 'Message Assistant IA E.A.S Sarlu');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = widget.message.role == 'user';
    final timeStr = DateFormat('HH:mm').format(widget.message.timestamp);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espace.xs + 2),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: Espace.sm),
          ],

          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Bulle de contenu principal
                Container(
                  padding: const EdgeInsets.all(Espace.md),
                  decoration: BoxDecoration(
                    color: isUser
                        ? scheme.primary
                        : scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(Rayon.lg),
                      topRight: const Radius.circular(Rayon.lg),
                      bottomLeft: isUser
                          ? const Radius.circular(Rayon.lg)
                          : const Radius.circular(6),
                      bottomRight: isUser
                          ? const Radius.circular(6)
                          : const Radius.circular(Rayon.lg),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isUser)
                        SelectableText(
                          widget.message.content,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimary,
                            height: 1.4,
                          ),
                        )
                      else
                        _RichMarkdownContent(text: widget.message.content),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // Barre d'actions / Métadonnées en dessous de la bulle
                Wrap(
                  spacing: Espace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      timeStr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),

                    // Bouton Copier rapide pour les messages de l'utilisateur
                    if (isUser) ...[
                      InkWell(
                        onTap: () => _handleCopy(context, 'Votre message'),
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  _copied
                                      ? Icons.check_circle_rounded
                                      : Icons.copy_rounded,
                                  key: ValueKey(_copied),
                                  size: 13,
                                  color: _copied
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _copied ? 'Copié' : 'Copier',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  fontWeight: _copied
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _copied
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // Barre d'actions pour les réponses de l'IA
                    if (!isUser) ...[
                      // Bouton Copier Réponse IA
                      InkWell(
                        onTap: () =>
                            _handleCopy(context, 'La réponse de l\'IA'),
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _copied
                                ? scheme.primary.withValues(alpha: 0.12)
                                : scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(Rayon.pilule),
                            border: Border.all(
                              color: _copied
                                  ? scheme.primary.withValues(alpha: 0.3)
                                  : scheme.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  _copied
                                      ? Icons.check_circle_rounded
                                      : Icons.content_copy_rounded,
                                  key: ValueKey(_copied),
                                  size: 12,
                                  color: _copied
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _copied ? 'Copié !' : 'Copier',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  fontWeight: _copied
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: _copied
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bouton Écouter — la réponse lue par le téléphone.
                      Consumer(
                        builder: (context, ref, _) {
                          final etat = ref.watch(voixProvider);
                          if (!etat.config.active || etat.indisponible) {
                            return const SizedBox.shrink();
                          }
                          final id = _idVocal(widget.message);
                          final enCours = etat.enLecture == id;
                          return _PastilleAction(
                            icone: enCours
                                ? Icons.stop_rounded
                                : Icons.volume_up_rounded,
                            libelle: enCours ? 'Arrêter' : 'Écouter',
                            accentue: enCours,
                            onTap: () => ref
                                .read(voixProvider.notifier)
                                .parler(id, widget.message.content),
                          );
                        },
                      ),

                      // Bouton Partager
                      InkWell(
                        onTap: () => _handleShare(widget.message.content),
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(Rayon.pilule),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.share_outlined,
                                size: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Partager',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bouton Régénérer (si dernière réponse IA)
                      if (widget.isLastAssistantMessage &&
                          widget.onRegenerate != null) ...[
                        InkWell(
                          onTap: widget.onRegenerate,
                          borderRadius: BorderRadius.circular(Rayon.pilule),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius:
                                  BorderRadius.circular(Rayon.pilule),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 12,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Régénérer',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),

          if (isUser) ...[
            const SizedBox(width: Espace.xs + 2),
            CircleAvatar(
              radius: 17,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.person_rounded,
                  size: 18, color: scheme.primary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Identifie un message pour la lecture vocale. `ChatMessage` n'a pas
/// d'identifiant propre ; l'horodatage à la microseconde en tient lieu, et il
/// suffit à savoir quelle bulle doit afficher « Arrêter ».
String _idVocal(ChatMessage message) =>
    '${message.timestamp.microsecondsSinceEpoch}';

/// Une action en pastille sous une bulle, au format des boutons voisins.
class _PastilleAction extends StatelessWidget {
  final IconData icone;
  final String libelle;
  final bool accentue;
  final VoidCallback onTap;

  const _PastilleAction({
    required this.icone,
    required this.libelle,
    required this.onTap,
    this.accentue = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final couleur = accentue ? scheme.primary : scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Rayon.pilule),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: accentue
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Rayon.pilule),
          border: Border.all(
            color: accentue
                ? scheme.primary.withValues(alpha: 0.3)
                : scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 12, color: couleur),
            const SizedBox(width: 4),
            Text(
              libelle,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: couleur,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Rendu Markdown Enrichi & Sélectionnable ---
class _RichMarkdownContent extends StatelessWidget {
  final String text;

  const _RichMarkdownContent({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Découper la trace de données consultées (« _Consulté : ..._ »)
    String bodyText = text;
    String? traceText;

    final traceRegex = RegExp(r'\n\n_Consulté\s*:\s*(.*?)_$', dotAll: true);
    final match = traceRegex.firstMatch(text);
    if (match != null) {
      bodyText = text.substring(0, match.start);
      traceText = match.group(1);
    }

    // Découper entre les blocs de code markdown (```...```) et le texte ordinaire
    final codeBlockRegex = RegExp(r'```(\w*)\n(.*?)```', dotAll: true);
    final List<Widget> children = [];
    int lastEnd = 0;

    for (final m in codeBlockRegex.allMatches(bodyText)) {
      if (m.start > lastEnd) {
        final plainPart = bodyText.substring(lastEnd, m.start);
        children.addAll(_parseTextBlocks(context, plainPart));
      }
      final lang = m.group(1);
      final code = m.group(2) ?? '';
      children.add(_CodeBlockWidget(code: code, language: lang));
      lastEnd = m.end;
    }

    if (lastEnd < bodyText.length) {
      final plainPart = bodyText.substring(lastEnd);
      children.addAll(_parseTextBlocks(context, plainPart));
    }

    // Module badge d'information sur les sources consultées
    if (traceText != null && traceText.isNotEmpty) {
      children.add(const SizedBox(height: Espace.xs));
      children.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(Rayon.sm),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.manage_search_rounded,
                  size: 15, color: scheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: SelectableText(
                  'Consulté : $traceText',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: scheme.primary,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  List<Widget> _parseTextBlocks(BuildContext context, String rawText) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = rawText.split('\n');
    final List<Widget> widgets = [];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 4));
        continue;
      }

      // Titres Markdown (#, ##, ###)
      if (trimmed.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: _renderRichText(
            context,
            trimmed.substring(2),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
        ));
      } else if (trimmed.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: _renderRichText(
            context,
            trimmed.substring(3),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
        ));
      } else if (trimmed.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: _renderRichText(
            context,
            trimmed.substring(4),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
        ));
      }
      // Puces de liste (- , * , • )
      else if (trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.startsWith('• ')) {
        final content = trimmed.substring(2);
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 7, right: 8),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: _renderRichText(context, content),
              ),
            ],
          ),
        ));
      }
      // Blockquote (> )
      else if (trimmed.startsWith('> ')) {
        final content = trimmed.substring(2);
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: scheme.primary, width: 3),
            ),
            color: scheme.primary.withValues(alpha: 0.05),
          ),
          child: _renderRichText(context, content,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              )),
        ));
      }
      // Texte ordinaire
      else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: _renderRichText(context, line),
        ));
      }
    }

    return widgets;
  }

  Widget _renderRichText(BuildContext context, String text, {TextStyle? style}) {
    final theme = Theme.of(context);
    final baseStyle = style ??
        theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.45,
        );

    final regex = RegExp(r'(\*\*(.*?)\*\*|`(.*?)`)');
    final matches = regex.allMatches(text).toList();

    if (matches.isEmpty) {
      return SelectableText(text, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      final matchStr = match.group(0) ?? '';
      if (matchStr.startsWith('**') && matchStr.endsWith('**')) {
        final boldContent = match.group(2) ?? '';
        spans.add(TextSpan(
          text: boldContent,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      } else if (matchStr.startsWith('`') && matchStr.endsWith('`')) {
        final codeContent = match.group(3) ?? '';
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              codeContent,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
              ),
            ),
          ),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return SelectableText.rich(
      TextSpan(style: baseStyle, children: spans),
    );
  }
}

// --- Bloc de Code Stylisé avec Copie ---
class _CodeBlockWidget extends StatefulWidget {
  final String code;
  final String? language;

  const _CodeBlockWidget({required this.code, this.language});

  @override
  State<_CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<_CodeBlockWidget> {
  bool _copied = false;

  void _copyCode(BuildContext context) {
    _copyToClipboard(context, widget.code, label: 'Code');
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : const Color(0xFF282C34),
        borderRadius: BorderRadius.circular(Rayon.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // En-tête du bloc de code avec bouton de copie
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(Rayon.md)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  (widget.language == null || widget.language!.isEmpty)
                      ? 'CODE'
                      : widget.language!.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                InkWell(
                  onTap: () => _copyCode(context),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 13,
                          color: _copied ? Colors.greenAccent : Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copié !' : 'Copier le code',
                          style: TextStyle(
                            color:
                                _copied ? Colors.greenAccent : Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Contenu du code sélectionnable
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code.trimRight(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFABB2BF),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Modale de l'historique des discussions ---
class _HistoriqueSessionsSheet extends ConsumerStatefulWidget {
  const _HistoriqueSessionsSheet();

  @override
  ConsumerState<_HistoriqueSessionsSheet> createState() =>
      __HistoriqueSessionsSheetState();
}

class __HistoriqueSessionsSheetState
    extends ConsumerState<_HistoriqueSessionsSheet> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sessionsState = ref.watch(chatSessionsProvider);
    final notifier = ref.read(chatSessionsProvider.notifier);

    final filteredSessions = sessionsState.sessions.where((s) {
      if (_searchQuery.isEmpty) return true;
      return s.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.messages.any(
              (m) => m.content.toLowerCase().contains(_searchQuery.toLowerCase()));
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: Rayon.feuille,
          ),
          child: Column(
            children: [
              const PoigneeFeuille(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(Espace.sm),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(Rayon.sm),
                      ),
                      child:
                          Icon(Icons.history_rounded, color: scheme.primary),
                    ),
                    const SizedBox(width: Espace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Historique des Discussions',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${sessionsState.sessions.length} conversation(s)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        notifier.createNewSession();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Espace.md, vertical: Espace.xs),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Nouvelle'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Espace.sm),

              // Barre de recherche dans les sessions
              if (sessionsState.sessions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Espace.page),
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une conversation…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: scheme.surfaceContainerLow,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Espace.md,
                        vertical: Espace.xs,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Rayon.pilule),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: Espace.xs),
              const Divider(height: 1),

              Expanded(
                child: filteredSessions.isEmpty
                    ? EtatVide(
                        message: _searchQuery.isEmpty
                            ? 'Aucun historique'
                            : 'Aucun résultat trouvé',
                        description: _searchQuery.isEmpty
                            ? 'Vos anciennes conversations s\'afficheront ici.'
                            : 'Essayez un autre mot-clé de recherche.',
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.all(Espace.page),
                        itemCount: filteredSessions.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: Espace.xs),
                        itemBuilder: (context, index) {
                          final session = filteredSessions[index];
                          final estActive =
                              session.id == sessionsState.activeId;

                          return Container(
                            decoration: BoxDecoration(
                              color: estActive
                                  ? scheme.primary.withValues(alpha: 0.12)
                                  : scheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(Rayon.md),
                              border: Border.all(
                                color: estActive
                                    ? scheme.primary
                                    : scheme.outlineVariant,
                              ),
                            ),
                            child: ListTile(
                              onTap: () {
                                notifier.selectSession(session.id);
                                Navigator.pop(context);
                              },
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: estActive
                                      ? scheme.primary
                                      : scheme.surfaceContainerHigh,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 18,
                                  color: estActive
                                      ? scheme.onPrimary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              title: Text(
                                session.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: estActive
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: estActive
                                      ? scheme.primary
                                      : scheme.onSurface,
                                ),
                              ),
                              subtitle: Text(
                                '${DateFormat('dd/MM HH:mm', 'fr_FR').format(session.date)} • ${session.messages.length} message(s)',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline_rounded,
                                    size: 20, color: scheme.error),
                                onPressed: () =>
                                    notifier.deleteSession(session.id),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
