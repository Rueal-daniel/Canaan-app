import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/gallery_service.dart';
import '../../services/notification_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/gallery_viewer.dart';

/// Admin → Management → School Gallery.
///
/// Creates gallery posts with multiple device photos (multi photo picker
/// with thumbnails + remove before publishing), manages every post
/// (View | Edit | Delete, add/remove individual photos), and publishes
/// to teachers/students with bell notifications scoped to the section.
class AdminSchoolGalleryPage extends StatefulWidget {
  final String adminName;
  const AdminSchoolGalleryPage({super.key, this.adminName = ''});

  @override
  State<AdminSchoolGalleryPage> createState() => _AdminSchoolGalleryPageState();
}

class _PickedPhoto {
  final String name;
  final Uint8List bytes;
  _PickedPhoto(this.name, this.bytes);
}

class _AdminSchoolGalleryPageState extends State<AdminSchoolGalleryPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _eventDescController = TextEditingController();

  DateTime? _eventDate;
  String _eventType = GalleryService.typeSundaySchool;
  String _section = GalleryService.sectionAll;

  final List<_PickedPhoto> _pickedNew = [];
  List<Map<String, dynamic>> _existingPhotos = [];
  final List<Map<String, dynamic>> _photosToDelete = [];

  bool _showForm = false;
  bool _isSaving = false;
  String _saveStatus = '';
  bool _isLoading = true;
  String? _loadError;
  int? _editingId;

  String _search = '';
  String _filterType = '';
  String _filterSection = '';
  String _filterMonth = '';

  List<Map<String, dynamic>> _posts = [];
  Map<int, List<Map<String, dynamic>>> _photosByGallery = {};
  final List<StreamSubscription> _realtimeSubs = [];

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _eventDescController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  void _subscribeRealtime() {
    for (final t in [
      GalleryService.postsTable,
      GalleryService.photosTable,
    ]) {
      try {
        _realtimeSubs.add(_client
            .from(t)
            .stream(primaryKey: ['id'])
            .listen((_) {
          if (mounted) _fetchAll(silent: true);
        }));
      } catch (_) {}
    }
  }

  Future<void> _fetchAll({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final results = await Future.wait([
        _client
            .from(GalleryService.postsTable)
            .select('*')
            .order('created_at', ascending: false),
        _client
            .from(GalleryService.photosTable)
            .select('*')
            .order('display_order', ascending: true),
      ]);
      if (mounted) {
        final posts = List<Map<String, dynamic>>.from(results[0] as List);
        final photos = List<Map<String, dynamic>>.from(results[1] as List);
        setState(() {
          _posts = posts;
          _photosByGallery = GalleryService.photosByGallery(photos);
          _isLoading = false;
          _loadError = null;
          if (_editingId != null) {
            _existingPhotos = List<Map<String, dynamic>>.from(
                _photosByGallery[_editingId] ?? []);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load gallery. Check your connection and try again. ($e)';
        });
      }
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<Map<String, String?>> _adminIdentity() async {
    var name = widget.adminName;
    String? id;
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        id = session.userId;
        if (name.isEmpty) {
          final auth = AuthService();
          final profile = await auth.getUserById(
              userId: session.userId, role: UserRole.admin);
          name = (profile?['full_name'] ?? '').toString();
        }
      }
    } catch (_) {}
    return {'name': name.isEmpty ? 'Admin' : name, 'id': id};
  }

  // -- photo picking ---------------------------------------------------------------

  Future<void> _pickPhotos() async {
    try {
      final images = await ImagePicker().pickMultiImage(imageQuality: 85);
      if (images.isEmpty) return;
      var added = 0;
      for (final x in images) {
        if (!GalleryService.isImageName(x.name)) continue;
        try {
          final bytes = await x.readAsBytes();
          if (bytes.isEmpty) continue;
          _pickedNew.add(_PickedPhoto(
              x.name.isEmpty ? 'photo.jpg' : x.name, bytes));
          added++;
        } catch (_) {}
      }
      if (mounted) {
        setState(() {});
        _snack(
          added == 0
              ? 'No readable images selected.'
              : 'Added $added photo${added == 1 ? '' : 's'}.',
          added == 0 ? Colors.orange : const Color(0xFF1565C0),
        );
      }
    } catch (e) {
      _snack('Could not open photo picker. ($e)', Colors.red);
    }
  }

  int get _visibleExistingCount =>
      _existingPhotos.where((p) => !_photosToDelete.contains(p)).length;

  // -- save (create / update) ------------------------------------------------------------

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    final isNew = _editingId == null;
    final totalPhotos = _pickedNew.length + (isNew ? 0 : _visibleExistingCount);
    if (totalPhotos == 0) {
      _snack('Please add at least one photo.', Colors.orange);
      return;
    }
    setState(() {
      _isSaving = true;
      _saveStatus = 'Saving gallery…';
    });
    try {
      final identity = await _adminIdentity();
      final now = DateTime.now().toIso8601String();
      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'event_description': _eventDescController.text.trim(),
        'event_date': _eventDate == null
            ? null
            : '${_eventDate!.year.toString().padLeft(4, '0')}-'
                '${_eventDate!.month.toString().padLeft(2, '0')}-'
                '${_eventDate!.day.toString().padLeft(2, '0')}',
        'event_type': _eventType,
        'section': _section,
        'updated_at': now,
      };
      int galleryId;
      if (isNew) {
        payload['created_by'] = identity['name'];
        if ((identity['id'] ?? '').isNotEmpty) {
          payload['created_by_id'] = identity['id'];
        }
        try {
          final created = await _client
              .from(GalleryService.postsTable)
              .insert(payload)
              .select('id')
              .single();
          galleryId = (created['id'] as num).toInt();
        } catch (_) {
          payload.remove('created_by_id');
          final created = await _client
              .from(GalleryService.postsTable)
              .insert(payload)
              .select('id')
              .single();
          galleryId = (created['id'] as num).toInt();
        }
      } else {
        galleryId = _editingId!;
        await _client
            .from(GalleryService.postsTable)
            .update(payload)
            .eq('id', galleryId);
        // Remove photos the admin deleted while editing.
        for (final p in _photosToDelete) {
          await _deletePhotoRow(p, updateUi: false);
        }
      }

      // Upload newly picked photos.
      var order = 0;
      try {
        final existing = _photosByGallery[galleryId] ?? [];
        for (final p in existing) {
          final o = (p['display_order'] as num?)?.toInt() ?? 0;
          if (o >= order) order = o + 1;
        }
      } catch (_) {}
      var uploaded = 0;
      for (var i = 0; i < _pickedNew.length; i++) {
        final picked = _pickedNew[i];
        if (mounted) {
          setState(() => _saveStatus =
              'Uploading photo ${i + 1} of ${_pickedNew.length}…');
        }
        final path =
            GalleryService.storagePath(galleryId, picked.name);
        await _client.storage
            .from(GalleryService.bucket)
            .uploadBinary(
              path,
              picked.bytes,
              fileOptions: FileOptions(
                  contentType:
                      GalleryService.mimeFor(picked.name),
                  upsert: true),
            );
        await _client.from(GalleryService.photosTable).insert({
          'gallery_id': galleryId,
          'photo_url':
              GalleryService.publicUrl(_client, path),
          'storage_path': path,
          'display_order': order++,
        });
        uploaded++;
      }

      final savedTitle = _titleController.text.trim();
      final savedSection = _section;
      _resetForm();
      await _fetchAll(silent: true);
      _snack(
        isNew
            ? '✅ Gallery published! ($uploaded photo${uploaded == 1 ? '' : 's'})'
            : '✅ Gallery updated successfully!',
        Colors.green,
      );
      // 🔔 Notify the section (new galleries only, no edit spam).
      if (isNew) {
        try {
          await NotificationService.galleryPublished(
            galleryId: galleryId.toString(),
            title: savedTitle,
            section: savedSection,
          );
        } catch (_) {}
      }
    } catch (e) {
      _snack('Could not publish. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveStatus = '';
        });
      }
    }
  }

  /// Deletes one photo row + its storage object. Returns true on success.
  Future<bool> _deletePhotoRow(Map<String, dynamic> photo,
      {bool updateUi = true}) async {
    final id = (photo['id'] as num?)?.toInt();
    final path = GalleryService.storagePathOf(photo);
    try {
      if (path.isNotEmpty) {
        try {
          await _client.storage
              .from(GalleryService.bucket)
              .remove([path]);
        } catch (_) {}
      }
      if (id != null) {
        await _client
            .from(GalleryService.photosTable)
            .delete()
            .eq('id', id);
      }
      if (updateUi && mounted) {
        setState(() {
          for (final list in _photosByGallery.values) {
            list.removeWhere((p) => p['id'] == photo['id']);
          }
          _existingPhotos.removeWhere((p) => p['id'] == photo['id']);
          _photosToDelete.removeWhere((p) => p['id'] == photo['id']);
        });
      }
      return true;
    } catch (e) {
      _snack('Could not remove photo. ($e)', Colors.red);
      return false;
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    _descController.clear();
    _eventDescController.clear();
    if (mounted) {
      setState(() {
        _eventDate = null;
        _eventType = GalleryService.typeSundaySchool;
        _section = GalleryService.sectionAll;
        _pickedNew.clear();
        _existingPhotos = [];
        _photosToDelete.clear();
        _editingId = null;
        _showForm = false;
      });
    }
  }

  void _startEdit(Map<String, dynamic> post) {
    final id = GalleryService.postIdOf(post);
    _titleController.text = (post['title'] ?? '').toString();
    _descController.text = (post['description'] ?? '').toString();
    _eventDescController.text =
        (post['event_description'] ?? '').toString();
    setState(() {
      _eventDate = GalleryService.dateOf(post);
      _eventType =
          GalleryService.normalizeType(post['event_type']?.toString());
      _section =
          GalleryService.normalizeSection(post['section']?.toString());
      _pickedNew.clear();
      _photosToDelete.clear();
      _existingPhotos =
          List<Map<String, dynamic>>.from(_photosByGallery[id] ?? []);
      _editingId = id;
      _showForm = true;
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    _snack('Editing mode — add or remove photos, then save.',
        const Color(0xFF1565C0));
  }

  void _confirmDelete(Map<String, dynamic> post) {
    final id = GalleryService.postIdOf(post);
    final title = (post['title'] ?? 'this gallery').toString();
    final photos = List<Map<String, dynamic>>.from(
        _photosByGallery[id] ?? []);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Gallery?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text(
            'Delete "$title" and its ${photos.length} photo${photos.length == 1 ? '' : 's'}? This cannot be undone.',
            style:
                GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final paths = photos
                    .map(GalleryService.storagePathOf)
                    .where((p) => p.isNotEmpty)
                    .toList();
                if (paths.isNotEmpty) {
                  try {
                    await _client.storage
                        .from(GalleryService.bucket)
                        .remove(paths);
                  } catch (_) {}
                }
                await _client
                    .from(GalleryService.postsTable)
                    .delete()
                    .eq('id', id);
                if (_editingId == id) _resetForm();
                await _fetchAll(silent: true);
                _snack('Gallery deleted.', Colors.green);
              } catch (e) {
                _snack('Could not delete. Please try again. ($e)', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Delete',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // -- filters -------------------------------------------------------------------------

  List<String> get _monthOptions {
    final set = <String>{};
    for (final p in _posts) {
      final k = GalleryService.monthKeyOf(p);
      if (k.isNotEmpty) set.add(k);
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  String _monthOptionLabel(String ym) {
    final parts = ym.split('-');
    final y = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 1;
    if (y == 0) return ym;
    return GalleryService.monthLabel(y, m);
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _posts.where((p) {
      if (_filterType.isNotEmpty &&
          GalleryService.normalizeType(p['event_type']?.toString()) !=
              _filterType) {
        return false;
      }
      if (_filterSection.isNotEmpty &&
          GalleryService.normalizeSection(p['section']?.toString()) !=
              _filterSection) {
        return false;
      }
      if (_filterMonth.isNotEmpty &&
          GalleryService.monthKeyOf(p) != _filterMonth) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay =
            '${p['title']} ${p['description']} ${p['event_description']}'
                .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  // -- build --------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('School Gallery',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchAll(),
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 12),
              if (_showForm)
                _formCard()
              else
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() {
                      _showForm = true;
                      _editingId = null;
                    }),
                    icon: const Icon(Icons.add_rounded, size: 22),
                    label: Text('+ Add Gallery',
                        style: GoogleFonts.poppins(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Text('Published Galleries (${_filtered.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _searchBox(),
              const SizedBox(height: 10),
              _filtersRow(),
              const SizedBox(height: 12),
              _galleryList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    return FadeInSlide(
      index: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF14B8A6).withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.photo_library_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('School Gallery',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                      'Share event photos with teachers & students.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle:
          GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
      labelStyle:
          GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF1565C0), width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2)),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827))),
    );
  }

  Widget _formCard() {
    final isEditing = _editingId != null;
    return FadeInSlide(
      index: 1,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(isEditing ? 'Edit Gallery' : 'Add Gallery',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                ),
                TextButton.icon(
                  onPressed: _isSaving ? null : _resetForm,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text('Cancel',
                      style: GoogleFonts.poppins(fontSize: 12.5)),
                ),
              ]),
              const SizedBox(height: 14),
              _fieldLabel('Title'),
              TextFormField(
                controller: _titleController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    'Title', 'e.g. Christmas Special Program 2026'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Title is required'
                    : null,
              ),
              const SizedBox(height: 14),
              _fieldLabel('Description'),
              TextFormField(
                controller: _descController,
                maxLines: 2,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration('Description',
                    'Short caption shown under the title'),
              ),
              const SizedBox(height: 14),
              _fieldLabel('What was the Event / Activity?'),
              TextFormField(
                controller: _eventDescController,
                maxLines: 4,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration('Event details',
                    'Explain what happened at this event…'),
              ),
              const SizedBox(height: 14),
              _fieldLabel('Event Date'),
              InkWell(
                onTap: _isSaving
                    ? null
                    : () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _eventDate ?? now,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 5),
                        );
                        if (picked != null) {
                          setState(() => _eventDate = picked);
                        }
                      },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          size: 20, color: Color(0xFF1565C0)),
                      const SizedBox(width: 10),
                      Text(
                        _eventDate == null
                            ? 'Pick the event date'
                            : '${_eventDate!.day} ${_monthName(_eventDate!.month)}, ${_eventDate!.year}',
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: _eventDate == null
                                ? Colors.grey.shade400
                                : const Color(0xFF111827)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _fieldLabel('Event Type'),
              DropdownButtonFormField<String>(
                value: _eventType,
                items: const [
                  (GalleryService.typeSundaySchool, 'Sunday School'),
                  (GalleryService.typeActivity, 'Activity'),
                  (GalleryService.typeSpecial, 'Special Program'),
                  (GalleryService.typeOthers, 'Others'),
                ]
                    .map((o) => DropdownMenuItem(
                          value: o.$1,
                          child: Text(o.$2,
                              style:
                                  GoogleFonts.poppins(fontSize: 14)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _eventType = v);
                },
                decoration: _inputDecoration('Type', 'Event type'),
              ),
              const SizedBox(height: 14),
              _fieldLabel('Section'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in [
                    (GalleryService.sectionAll, 'All Sections'),
                    (GalleryService.sectionSubJunior, 'Sub Junior'),
                    (GalleryService.sectionJunior, 'Junior'),
                    (GalleryService.sectionSenior, 'Senior'),
                  ])
                    ChoiceChip(
                      label: Text(o.$2,
                          style: GoogleFonts.poppins(fontSize: 12.5)),
                      selected: _section == o.$1,
                      selectedColor: const Color(0xFF1565C0)
                          .withValues(alpha: 0.15),
                      checkmarkColor: const Color(0xFF1565C0),
                      onSelected: (_) =>
                          setState(() => _section = o.$1),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _fieldLabel('Photos / Attachments'),
              _photoPickerArea(),
              const SizedBox(height: 18),
              if (_isSaving) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(
                    color: Color(0xFF1565C0),
                    backgroundColor: Color(0xFFF1F5F9),
                  ),
                ),
                const SizedBox(height: 8),
                Text(_saveStatus,
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: Colors.grey.shade600)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.publish_rounded, size: 20),
                  label: Text(
                    isEditing ? 'Save Changes' : '🖼️ Publish Gallery',
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF0F766E)
                        .withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthName(int m) => const [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ][m - 1];

  Widget _photoPickerArea() {
    final visibleExisting = _existingPhotos
        .where((p) => !_photosToDelete.contains(p))
        .toList();
    final hasAny =
        visibleExisting.isNotEmpty || _pickedNew.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _isSaving ? null : _pickPhotos,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                const Text('🖼️', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text('Add Photos',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1565C0))),
                const SizedBox(height: 4),
                Text('Select multiple photos from your device',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5, color: Colors.grey.shade500)),
              ],
            ),
          ),
        ),
        if (hasAny) ...[
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount:
                visibleExisting.length + _pickedNew.length,
            itemBuilder: (_, i) {
              if (i < visibleExisting.length) {
                final photo = visibleExisting[i];
                final url =
                    GalleryService.photoUrlOf(photo);
                return _thumb(
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: const Color(0xFFE2E8F0),
                      child: const Icon(Icons.broken_image_rounded,
                          color: Colors.grey, size: 20),
                    ),
                  ),
                  onRemove: _isSaving
                      ? null
                      : () => setState(
                          () => _photosToDelete.add(photo)),
                );
              }
              final picked = _pickedNew[i - visibleExisting.length];
              return _thumb(
                Image.memory(picked.bytes, fit: BoxFit.cover),
                onRemove: _isSaving
                    ? null
                    : () =>
                        setState(() => _pickedNew.remove(picked)),
              );
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isSaving ? null : _pickPhotos,
            icon: const Icon(Icons.add_photo_alternate_rounded,
                size: 18),
            label: Text('+ Add More Photos',
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1565C0),
              side: const BorderSide(color: Color(0xFF1565C0)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _thumb(Widget image, {VoidCallback? onRemove}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox.expand(child: image),
        ),
        if (onRemove != null)
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _searchBox() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _search = v),
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: '🔍 Search gallery...',
        hintStyle:
            GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon:
            const Icon(Icons.search_rounded, color: Color(0xFF1565C0)),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 20),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _search = '');
                },
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFF1565C0), width: 2)),
      ),
    );
  }

  Widget _filtersRow() {
    Widget drop({
      required String value,
      required String hint,
      required List<(String, String)> options,
      required ValueChanged<String?> onChanged,
    }) {
      return Expanded(
        child: DropdownButtonFormField<String>(
          value: value.isEmpty ? null : value,
          // Tight 3-across row: let long labels (e.g. "September 2026")
          // ellipsize instead of overflowing the RenderFlex.
          isExpanded: true,
          hint: Text(hint,
              style: GoogleFonts.poppins(fontSize: 12.5),
              overflow: TextOverflow.ellipsis),
          items: [
            DropdownMenuItem(
                value: '',
                child:
                    Text('All', style: GoogleFonts.poppins(fontSize: 12.5))),
            ...options.map((o) => DropdownMenuItem(
                  value: o.$1,
                  child: Text(o.$2,
                      style: GoogleFonts.poppins(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200)),
          ),
          style: GoogleFonts.poppins(
              fontSize: 12.5, color: const Color(0xFF111827)),
        ),
      );
    }

    return Row(
      children: [
        drop(
          value: _filterType,
          hint: 'Type',
          options: const [
            (GalleryService.typeSundaySchool, 'Sunday School'),
            (GalleryService.typeActivity, 'Activity'),
            (GalleryService.typeSpecial, 'Special'),
            (GalleryService.typeOthers, 'Others'),
          ],
          onChanged: (v) => setState(() => _filterType = v ?? ''),
        ),
        const SizedBox(width: 8),
        drop(
          value: _filterSection,
          hint: 'Section',
          options: const [
            (GalleryService.sectionSubJunior, 'Sub Junior'),
            (GalleryService.sectionJunior, 'Junior'),
            (GalleryService.sectionSenior, 'Senior'),
          ],
          onChanged: (v) => setState(() => _filterSection = v ?? ''),
        ),
        const SizedBox(width: 8),
        drop(
          value: _filterMonth,
          hint: 'Month',
          options:
              _monthOptions.map((m) => (m, _monthOptionLabel(m))).toList(),
          onChanged: (v) => setState(() => _filterMonth = v ?? ''),
        ),
      ],
    );
  }

  Widget _galleryList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF1565C0))),
      );
    }
    if (_loadError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(_loadError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _fetchAll(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Retry',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }
    final items = _filtered;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Text('🖼️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text('No galleries found.',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
          const SizedBox(height: 4),
          Text('Tap + Add Gallery to share your first photos.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: Colors.grey.shade500)),
        ]),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _galleryCard(items[i]),
    );
  }

  Widget _galleryCard(Map<String, dynamic> post) {
    final id = GalleryService.postIdOf(post);
    final photos = _photosByGallery[id] ?? [];
    final cover = GalleryService.coverUrlOf(_photosByGallery, id);
    final date = GalleryService.prettyDate(post);
    final isEditingThis = _editingId == id && _editingId != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
            left: BorderSide(
                color: isEditingThis
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF14B8A6),
                width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 92,
                  height: 92,
                  child: cover == null
                      ? Container(
                          color: const Color(0xFFF1F5F9),
                          child: const Center(
                              child: Text('🖼️',
                                  style: TextStyle(fontSize: 32))),
                        )
                      : Image.network(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Center(
                                child: Icon(
                                    Icons.broken_image_rounded,
                                    color: Colors.grey)),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🖼️ ${(post['title'] ?? '').toString()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                    const SizedBox(height: 4),
                    if (date.isNotEmpty)
                      Text(date,
                          style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _pill(
                          GalleryService.prettyType(
                              post['event_type']?.toString()),
                          const Color(0xFF6D28D9)),
                      _pill(
                          GalleryService.prettySection(
                              post['section']?.toString()),
                          const Color(0xFF7B1FA2)),
                      _pill(
                          '🖼️ ${photos.length}',
                          Colors.grey.shade600),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => openGalleryDetail(
                  context,
                  post: post,
                  photos: photos,
                  accent: const Color(0xFF0F766E),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1565C0),
                  side: const BorderSide(color: Color(0xFF1565C0)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text('View',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded,
                  color: Color(0xFF1565C0), size: 20),
              tooltip: 'Edit',
              onPressed: () => _startEdit(post),
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded,
                  color: Colors.red, size: 20),
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(post),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}
