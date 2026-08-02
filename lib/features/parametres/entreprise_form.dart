import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../app/ui_kit.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_state.dart';
import '../../core/db/stores.dart';
import '../../core/models/models.dart';
import '../../core/reseau.dart';
import '../../core/sync/op_queue.dart';
import '../../core/sync/sync_engine.dart';

class EntrepriseForm extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const EntrepriseForm({super.key, this.isEmbedded = false});

  @override
  ConsumerState<EntrepriseForm> createState() => _EntrepriseFormState();
}

class _EntrepriseFormState extends ConsumerState<EntrepriseForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nomCtrl,
      _sloganCtrl,
      _adresseCtrl,
      _quartierCtrl,
      _villeCtrl,
      _telephoneCtrl,
      _emailCtrl,
      _siteWebCtrl,
      _rccmCtrl,
      _nifCtrl,
      _deviseCtrl,
      _conditionsCtrl,
      _mentionsCtrl,
      _signataireCtrl,
      _ribCtrl,
      _banqueCtrl,
      _swiftCtrl;
  String? _logoBase64;
  String? _signatureBase64;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nomCtrl = TextEditingController();
    _sloganCtrl = TextEditingController();
    _adresseCtrl = TextEditingController();
    _quartierCtrl = TextEditingController();
    _villeCtrl = TextEditingController();
    _telephoneCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _siteWebCtrl = TextEditingController();
    _rccmCtrl = TextEditingController();
    _nifCtrl = TextEditingController();
    _deviseCtrl = TextEditingController(text: 'GNF');
    _conditionsCtrl = TextEditingController();
    _mentionsCtrl = TextEditingController();
    _signataireCtrl = TextEditingController();
    _ribCtrl = TextEditingController();
    _banqueCtrl = TextEditingController();
    _swiftCtrl = TextEditingController();

    _chargerEntreprise();
  }

  void _chargerEntreprise() async {
    final stores = ref.read(storesProvider);
    final entreprise = await stores.getEntreprise();
    if (entreprise != null && mounted) {
      setState(() {
        _nomCtrl.text = entreprise.nom;
        _sloganCtrl.text = entreprise.slogan;
        _adresseCtrl.text = entreprise.adresse;
        _quartierCtrl.text = entreprise.quartier;
        _villeCtrl.text = entreprise.ville;
        _telephoneCtrl.text = entreprise.telephone;
        _emailCtrl.text = entreprise.email;
        _siteWebCtrl.text = entreprise.siteWeb;
        _rccmCtrl.text = entreprise.rccm;
        _nifCtrl.text = entreprise.nif;
        _deviseCtrl.text = entreprise.devise;
        _conditionsCtrl.text = entreprise.conditionsPaiement;
        _mentionsCtrl.text = entreprise.mentionsLegales;
        _signataireCtrl.text = entreprise.signataire;
        _ribCtrl.text = entreprise.rib;
        _banqueCtrl.text = entreprise.banque;
        _swiftCtrl.text = entreprise.swift;
        _logoBase64 = entreprise.logo.isNotEmpty ? entreprise.logo : null;
        _signatureBase64 = entreprise.signatureImage.isNotEmpty
            ? entreprise.signatureImage
            : null;
      });
    }
  }

  @override
  void dispose() {
    _nomCtrl.dispose();
    _sloganCtrl.dispose();
    _adresseCtrl.dispose();
    _quartierCtrl.dispose();
    _villeCtrl.dispose();
    _telephoneCtrl.dispose();
    _emailCtrl.dispose();
    _siteWebCtrl.dispose();
    _rccmCtrl.dispose();
    _nifCtrl.dispose();
    _deviseCtrl.dispose();
    _conditionsCtrl.dispose();
    _mentionsCtrl.dispose();
    _signataireCtrl.dispose();
    _ribCtrl.dispose();
    _banqueCtrl.dispose();
    _swiftCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isLogo) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 800);
    if (picked != null) {
      final bytes = await File(picked.path).readAsBytes();
      if (!mounted) return;
      setState(() {
        if (isLogo) {
          _logoBase64 = 'data:image/png;base64,${base64Encode(bytes)}';
        } else {
          _signatureBase64 = 'data:image/png;base64,${base64Encode(bytes)}';
        }
      });
    }
  }

  Future<void> _ouvrirPadSignature() async {
    final base64Result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SignaturePadDialog(),
    );
    if (base64Result != null && mounted) {
      setState(() {
        _signatureBase64 = base64Result;
      });
    }
  }

  Future<void> _enregistrer() async {
    if (!mounted || !_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final entreprise = Entreprise(
      nom: _nomCtrl.text.trim(),
      slogan: _sloganCtrl.text.trim(),
      adresse: _adresseCtrl.text.trim(),
      quartier: _quartierCtrl.text.trim(),
      ville: _villeCtrl.text.trim(),
      telephone: _telephoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      siteWeb: _siteWebCtrl.text.trim(),
      rccm: _rccmCtrl.text.trim(),
      nif: _nifCtrl.text.trim(),
      logo: _logoBase64 ?? '',
      tauxTVA: 0.0,
      devise: _deviseCtrl.text.trim(),
      conditionsPaiement: _conditionsCtrl.text.trim(),
      mentionsLegales: _mentionsCtrl.text.trim(),
      signataire: _signataireCtrl.text.trim(),
      signatureImage: _signatureBase64 ?? '',
      rib: _ribCtrl.text.trim(),
      banque: _banqueCtrl.text.trim(),
      swift: _swiftCtrl.text.trim(),
      couleurAccent: '#E85D04',
    );

    try {
      final stores = ref.read(storesProvider);
      await stores.upsert('entreprise', entreprise);

      // Récupérer la version sauvegardée localement (qui contient _rev si elle existait déjà)
      final savedEnt = await stores.getEntreprise();
      final entJson = savedEnt?.toJson() ?? entreprise.toJson();

      final opQueue = ref.read(opQueueProvider);
      await opQueue.enqueue('entreprise', {'record': entJson},
          libelle: 'Fiche entreprise');

      if (await aUneConnexion()) {
        try {
          final apiClient = ref.read(apiClientProvider);
          await apiClient.dio.post(kDataEntreprise, data: entJson);
        } catch (_) {}
      }

      ref.read(syncEngineProvider).demanderSynchro();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Fiche entreprise & signature enregistrées avec succès !')),
      );

      if (!widget.isEmbedded && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Informations sauvegardées localement (sync différée) : $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildFormContent(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Logos & Visuels
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo Carte
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOGO ENTREPRISE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: Espace.xs),
                    GestureDetector(
                      onTap: () => _pickImage(true),
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(Rayon.md),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: () {
                          final bytesLogo = bytesFromBase64(_logoBase64);
                          return bytesLogo != null
                              ? Stack(
                                  children: [
                                    Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(Espace.xs),
                                        child: Image.memory(
                                          bytesLogo,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) => Icon(
                                              Icons.broken_image_rounded,
                                              color: scheme.error),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: InkWell(
                                        onTap: () =>
                                            setState(() => _logoBase64 = null),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: scheme.error,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(Icons.close_rounded,
                                              size: 14, color: scheme.onError),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate_rounded,
                                        color: scheme.primary, size: 28),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Choisir un Logo',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                );
                        }(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Espace.md),

              // Signature Carte
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SIGNATURE / TAMPON',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: Espace.xs),
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(Rayon.md),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: () {
                        final bytesSig = bytesFromBase64(_signatureBase64);
                        return bytesSig != null
                            ? Stack(
                                children: [
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(Espace.xs),
                                      child: Image.memory(
                                        bytesSig,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => Icon(
                                            Icons.broken_image_rounded,
                                            color: scheme.error),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: InkWell(
                                      onTap: () => setState(
                                          () => _signatureBase64 = null),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: scheme.error,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(Icons.close_rounded,
                                            size: 14, color: scheme.onError),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      IconButton.filledTonal(
                                        icon: const Icon(
                                            Icons.gesture_rounded,
                                            size: 20),
                                        tooltip: 'Signer à l\'écran',
                                        onPressed: _ouvrirPadSignature,
                                      ),
                                      const SizedBox(width: Espace.xs),
                                      IconButton.filledTonal(
                                        icon: const Icon(
                                            Icons.image_search_rounded,
                                            size: 20),
                                        tooltip: 'Importer une photo',
                                        onPressed: () => _pickImage(false),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Signer ou importer',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              );
                      }(),
                    ),
                    if (_signatureBase64 != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: _ouvrirPadSignature,
                            icon: const Icon(Icons.edit_rounded, size: 14),
                            label: const Text('Redessiner',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.lg),

          // 2. Identité & Contact
          Text(
            'IDENTITÉ & COORDONNÉES',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: Espace.xs),
          TextFormField(
            controller: _nomCtrl,
            decoration: const InputDecoration(
              labelText: 'Nom de l\'entreprise *',
              prefixIcon: Icon(Icons.business_rounded),
            ),
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Le nom est obligatoire'
                : null,
          ),
          const SizedBox(height: Espace.sm),
          TextFormField(
            controller: _sloganCtrl,
            decoration: const InputDecoration(
              labelText: 'Slogan / Description courte',
              prefixIcon: Icon(Icons.subtitles_rounded),
            ),
          ),
          const SizedBox(height: Espace.sm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _telephoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Téléphone',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                ),
              ),
              const SizedBox(width: Espace.sm),
              Expanded(
                child: TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.sm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _adresseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Adresse',
                    prefixIcon: Icon(Icons.location_on_rounded),
                  ),
                ),
              ),
              const SizedBox(width: Espace.sm),
              Expanded(
                child: TextFormField(
                  controller: _villeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ville',
                    prefixIcon: Icon(Icons.location_city_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.lg),

          // 3. Fiscalité & Mentions
          Text(
            'FACTURATION & RÉGLEMENTATION',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: Espace.xs),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _nifCtrl,
                  decoration: const InputDecoration(
                    labelText: 'NIF',
                    prefixIcon: Icon(Icons.badge_rounded),
                  ),
                ),
              ),
              const SizedBox(width: Espace.sm),
              Expanded(
                child: TextFormField(
                  controller: _rccmCtrl,
                  decoration: const InputDecoration(
                    labelText: 'RCCM',
                    prefixIcon: Icon(Icons.gavel_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.sm),
          TextFormField(
            controller: _deviseCtrl,
            decoration: const InputDecoration(
              labelText: 'Devise par défaut',
              prefixIcon: Icon(Icons.monetization_on_rounded),
            ),
          ),
          const SizedBox(height: Espace.sm),
          TextFormField(
            controller: _conditionsCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Conditions de paiement',
              prefixIcon: Icon(Icons.note_alt_rounded),
            ),
          ),
          const SizedBox(height: Espace.sm),
          TextFormField(
            controller: _signataireCtrl,
            decoration: const InputDecoration(
              labelText: 'Nom du Signataire principal',
              prefixIcon: Icon(Icons.person_pin_rounded),
            ),
          ),
          const SizedBox(height: Espace.lg),

          // 4. Coordonnées bancaires
          Text(
            'COORDONNÉES BANCAIRES (RIB / SWIFT)',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: Espace.xs),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _banqueCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nom de la Banque',
                    prefixIcon: Icon(Icons.account_balance_rounded),
                  ),
                ),
              ),
              const SizedBox(width: Espace.sm),
              Expanded(
                child: TextFormField(
                  controller: _swiftCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Code SWIFT',
                    prefixIcon: Icon(Icons.code_rounded),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.sm),
          TextFormField(
            controller: _ribCtrl,
            decoration: const InputDecoration(
              labelText: 'Numéro de Compte / RIB / IBAN',
              prefixIcon: Icon(Icons.credit_card_rounded),
            ),
          ),
          const SizedBox(height: Espace.xl),

          // Bouton d'enregistrement
          AppButton(
            label: _isLoading ? 'Enregistrement…' : 'Enregistrer la Fiche',
            icon: Icons.save_rounded,
            onPressed: _isLoading ? null : _enregistrer,
            expanded: true,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEmbedded) {
      return _buildFormContent(context);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fiche Entreprise')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Espace.page),
        child: _buildFormContent(context),
      ),
    );
  }
}

// --- Modèle de Trait pour la Signature Tactile ---
class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;

  _Stroke({
    required this.points,
    required this.color,
    required this.width,
  });
}

// --- Custom Painter pour le rendu vectoriel de la signature ---
class _SignaturePainter extends CustomPainter {
  final List<_Stroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentWidth;

  _SignaturePainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fond blanc propre
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Dessiner tous les traits validés
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke.points, stroke.color, stroke.width);
    }
    // Dessiner le trait en cours
    _drawStroke(canvas, currentPoints, currentColor, currentWidth);
  }

  void _drawStroke(
      Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;

    if (points.length == 1) {
      canvas.drawCircle(points.first, width / 2, paint);
      return;
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// --- Dialogue Interactif de Signature Tactile ---
class _SignaturePadDialog extends StatefulWidget {
  const _SignaturePadDialog();

  @override
  State<_SignaturePadDialog> createState() => _SignaturePadDialogState();
}

class _SignaturePadDialogState extends State<_SignaturePadDialog> {
  final List<_Stroke> _strokes = [];
  final List<Offset> _currentPoints = [];
  Color _selectedColor = Colors.black;
  final double _strokeWidth = 3.5;
  bool _isSaving = false;

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentPoints.clear();
      _currentPoints.add(details.localPosition);
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _currentPoints.add(details.localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_currentPoints.isNotEmpty) {
      setState(() {
        _strokes.add(_Stroke(
          points: List.from(_currentPoints),
          color: _selectedColor,
          width: _strokeWidth,
        ));
        _currentPoints.clear();
      });
    }
  }

  void _effacer() {
    setState(() {
      _strokes.clear();
      _currentPoints.clear();
    });
  }

  void _annuler() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _strokes.removeLast();
      });
    }
  }

  Future<void> _valider() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez d\'abord tracer votre signature')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final recorder = ui.PictureRecorder();
      const canvasSize = Size(600, 300);
      final canvas = Canvas(recorder);

      final painter = _SignaturePainter(
        strokes: _strokes,
        currentPoints: const [],
        currentColor: _selectedColor,
        currentWidth: _strokeWidth,
      );
      painter.paint(canvas, canvasSize);

      final picture = recorder.endRecording();
      final image =
          await picture.toImage(canvasSize.width.toInt(), canvasSize.height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final bytes = byteData.buffer.asUint8List();
        final base64String = 'data:image/png;base64,${base64Encode(bytes)}';
        if (mounted) {
          Navigator.pop(context, base64String);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la création : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rayon.lg)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(Espace.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.gesture_rounded, color: scheme.primary),
                ),
                const SizedBox(width: Espace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signature Tactile',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Tracez votre signature au doigt ou au stylet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: Espace.md),

            // Zone de Dessin Tactile
            ClipRRect(
              borderRadius: BorderRadius.circular(Rayon.md),
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 1.5),
                  borderRadius: BorderRadius.circular(Rayon.md),
                ),
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: CustomPaint(
                    painter: _SignaturePainter(
                      strokes: _strokes,
                      currentPoints: _currentPoints,
                      currentColor: _selectedColor,
                      currentWidth: _strokeWidth,
                    ),
                    child: Stack(
                      children: [
                        if (_strokes.isEmpty && _currentPoints.isEmpty)
                          Center(
                            child: Text(
                              'Signez ici dans le cadre',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: Colors.grey.shade400,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Espace.sm),

            // Barre d'outils (Couleur & Effacement)
            Row(
              children: [
                // Choix Couleur Encre
                Text(
                  'Encre :',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() => _selectedColor = Colors.black),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedColor == Colors.black
                            ? scheme.primary
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _selectedColor = const Color(0xFF002366)),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFF002366),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedColor == const Color(0xFF002366)
                            ? scheme.primary
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
                const Spacer(),

                // Boutons Annuler & Effacer
                TextButton.icon(
                  onPressed: _strokes.isNotEmpty ? _annuler : null,
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('Annuler'),
                ),
                TextButton.icon(
                  onPressed: _strokes.isNotEmpty ? _effacer : null,
                  icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                  label: const Text('Effacer'),
                ),
              ],
            ),
            const SizedBox(height: Espace.md),

            // Actions d'enregistrement
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: Espace.sm),
                Expanded(
                  child: AppButton(
                    label: _isSaving ? 'Génération…' : 'Appliquer',
                    icon: Icons.check_rounded,
                    onPressed: _isSaving ? null : _valider,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
