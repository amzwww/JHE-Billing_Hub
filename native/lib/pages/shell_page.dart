import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/bills_service.dart';
import '../services/desktop_notification_service.dart';
import 'billing_requests_page.dart';
import 'clients_page.dart';
import 'document_editor_page.dart';
import 'documents_page.dart';
import 'home_page.dart';
import 'issuers_page.dart';
import 'jon_options_page.dart';
import 'ponencias_page.dart';
import 'users_roles_page.dart';

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  final _service = BillsService();
  final _desktopNotifications = DesktopNotificationService();
  final Set<String> _announcedNotifications = {};
  String? _role;
  List<Map<String, dynamic>> _issuers = [];
  List<Map<String, dynamic>> _notifications = [];
  int _requestsToInvoice = 0;
  int _unreadNotifications = 0;
  int _invoiceRefreshToken = 0;
  int _quoteRefreshToken = 0;
  int _selected = 0;
  bool _menuOpen = false;
  Timer? _refreshTimer;
  Timer? _menuCloseTimer;
  bool _pointerInsideMenu = false;

  bool get _admin => _role == 'admin';

  @override
  void initState() {
    super.initState();
    unawaited(_initializeDesktopNotifications());
    _loadRole();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshCounters(),
    );
  }

  Future<void> _initializeDesktopNotifications() async {
    try {
      await _desktopNotifications.initialize();
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _menuCloseTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRole() async {
    try {
      final values = await Future.wait([
        _service.currentRole(),
        _service.issuers(),
        _service.notifications(),
      ]);
      final role = values[0] as String;
      final notifications = List<Map<String, dynamic>>.from(values[2] as List);
      var requests = 0;
      if (role == 'admin')
        requests = await _service.billingRequestsToInvoiceCount();
      if (mounted) {
        setState(() {
          _role = role;
          _issuers = List<Map<String, dynamic>>.from(values[1] as List);
          _notifications = notifications;
          _unreadNotifications = notifications
              .where((row) => row['read_at'] == null)
              .length;
          _requestsToInvoice = requests;
        });
        unawaited(_announceUnreadNotifications(notifications));
      }
    } catch (error) {
      if (mounted) _message('No se pudo cargar el perfil: $error');
    }
  }

  Future<void> _refreshCounters() async {
    try {
      final values = await Future.wait([
        _service.notifications(),
        if (_admin) _service.billingRequestsToInvoiceCount(),
      ]);
      final notifications = List<Map<String, dynamic>>.from(
        values.first as List,
      );
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _unreadNotifications = notifications
              .where((row) => row['read_at'] == null)
              .length;
          if (_admin && values.length > 1) {
            _requestsToInvoice = values[1] as int;
          }
        });
        unawaited(_announceUnreadNotifications(notifications));
      }
    } catch (_) {}
  }

  Future<void> _announceUnreadNotifications(
    List<Map<String, dynamic>> notifications,
  ) async {
    for (final row in notifications.reversed) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty || row['read_at'] != null) continue;
      if (!_announcedNotifications.add(id)) continue;
      try {
        await _desktopNotifications.show(
          id: id,
          title: row['title']?.toString() ?? 'JHE Billing Hub',
          body: row['body']?.toString() ?? '',
          onClick: () => unawaited(_handleNotificationSelection(id)),
        );
      } catch (_) {}
    }
  }

  Future<void> _newInvoice(String issuer, String type) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentEditorPage(
          isQuote: false,
          initialIssuer: issuer,
          initialType: type,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _invoiceRefreshToken++;
        _selected = _admin ? 2 : 1;
      });
    }
  }

  Future<void> _newQuote() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const DocumentEditorPage(isQuote: true),
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _quoteRefreshToken++;
        _selected = _admin ? 3 : 2;
      });
    }
  }

  Future<void> _chooseJon() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => JonOptionsPage(
          onInvoice: (type) => _newInvoice('JHE', type),
          onQuote: _newQuote,
        ),
      ),
    );
  }

  void _select(int index) => setState(() {
    if ((_admin && index == 2) || (!_admin && index == 1)) {
      _invoiceRefreshToken++;
    }
    if ((_admin && index == 3) || (!_admin && index == 2)) {
      _quoteRefreshToken++;
    }
    _selected = index;
    _menuOpen = _pointerInsideMenu;
  });

  void _openDesktopMenu() {
    _menuCloseTimer?.cancel();
    _pointerInsideMenu = true;
    if (mounted && !_menuOpen) setState(() => _menuOpen = true);
  }

  void _scheduleDesktopMenuClose() {
    _pointerInsideMenu = false;
    _menuCloseTimer?.cancel();
    _menuCloseTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted && !_pointerInsideMenu && _menuOpen) {
        setState(() => _menuOpen = false);
      }
    });
  }

  Future<void> _markNotificationRead(String id) async {
    try {
      await _service.markNotificationRead(id);
      if (!mounted) return;
      setState(() {
        final row = _notifications
            .where((item) => item['id']?.toString() == id)
            .firstOrNull;
        if (row != null && row['read_at'] == null) {
          row['read_at'] = DateTime.now().toUtc().toIso8601String();
          _unreadNotifications = (_unreadNotifications - 1)
              .clamp(0, 9999)
              .toInt();
        }
      });
    } catch (error) {
      if (mounted) _message('No se pudo marcar el aviso: $error');
    }
  }

  Future<void> _handleNotificationSelection(String id) async {
    if (id == '__mark_all__') {
      await _markAllNotificationsRead();
      return;
    }

    final notification = _notifications
        .where((row) => row['id']?.toString() == id)
        .firstOrNull;
    await _markNotificationRead(id);
    if (!mounted || notification == null) return;
    if (!_admin ||
        notification['kind']?.toString() != 'document_modification_requested') {
      return;
    }

    var documentType = notification['entity_type']?.toString() ?? '';
    var documentId = notification['entity_id']?.toString() ?? '';
    var requestText = _notificationRequestText(
      notification['body']?.toString() ?? '',
    );
    var documentNumber = _notificationDocumentNumber(
      notification['body']?.toString() ?? '',
    );

    if (documentType == 'document_modification_request' &&
        documentId.isNotEmpty) {
      try {
        final request = await _service.modificationRequest(documentId);
        if (request != null) {
          documentType = request['document_type']?.toString() ?? '';
          documentId = request['document_id']?.toString() ?? '';
          documentNumber = request['document_number']?.toString() ?? '';
          requestText = request['request_text']?.toString() ?? requestText;
        }
      } catch (error) {
        if (mounted) _message('No se pudo leer la solicitud: $error');
        return;
      }
    }

    if (!const {'invoice', 'quote'}.contains(documentType) ||
        documentId.isEmpty) {
      _message('El aviso no está vinculado a un documento válido.');
      return;
    }

    try {
      final isQuote = documentType == 'quote';
      setState(() => _selected = isQuote ? 3 : 2);

      var document = await _service.documentById(
        documentType: documentType,
        id: documentId,
      );
      if (document == null && documentNumber.isNotEmpty) {
        document = await _service.documentByNumber(
          documentType: documentType,
          documentNumber: documentNumber,
        );
      }
      if (!mounted) return;
      if (document == null) {
        _message('El documento solicitado ya no existe.');
        return;
      }

      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentEditorPage(
            isQuote: isQuote,
            existing: document,
            modificationRequest: requestText,
          ),
        ),
      );
      if (changed == true && mounted) {
        setState(() {
          if (isQuote) {
            _quoteRefreshToken++;
            _selected = 3;
          } else {
            _invoiceRefreshToken++;
            _selected = 2;
          }
        });
        await _refreshCounters();
      }
    } catch (error) {
      if (mounted) _message('No se pudo abrir el documento: $error');
    }
  }

  String _notificationRequestText(String body) {
    final separator = body.indexOf(': ');
    return separator < 0 ? body.trim() : body.substring(separator + 2).trim();
  }

  String _notificationDocumentNumber(String body) {
    return RegExp(
          r'\b[A-Z0-9]+-(?:(?:PF|REC)-)?\d{4}-\d{3}\b',
          caseSensitive: false,
        ).firstMatch(body)?.group(0) ??
        '';
  }

  Future<void> _markAllNotificationsRead() async {
    try {
      await _service.markAllNotificationsRead();
      final notifications = await _service.notifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _unreadNotifications = notifications
            .where((row) => row['read_at'] == null)
            .length;
      });
      if (_unreadNotifications > 0) {
        throw StateError('Quedan avisos sin actualizar en la base de datos.');
      }
    } catch (error) {
      if (mounted) _message('No se pudieron marcar los avisos: $error');
    }
  }

  Future<void> _signOut() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres cerrar la sesión actual?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (accepted == true) await _service.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_role == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final admin = _admin;
    final pages = admin ? _adminPages() : _gestionPages();
    if (_selected >= pages.length) _selected = 0;
    final content = IndexedStack(index: _selected, children: pages);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        if (compact) {
          final destinations = _destinations(admin);
          final selected = _selected < destinations.length ? _selected : 0;
          return Scaffold(
            drawer: Drawer(child: _mobileMenu(admin)),
            body: Column(
              children: [
                Material(
                  color: Colors.white,
                  elevation: 1,
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: 62,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Builder(
                              builder: (scaffoldContext) => IconButton(
                                tooltip: 'Abrir menú',
                                onPressed: Scaffold.of(
                                  scaffoldContext,
                                ).openDrawer,
                                icon: const Icon(Icons.menu_rounded),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                destinations[selected].$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: SafeArea(top: false, child: content)),
              ],
            ),
          );
        }
        final scaffold = Scaffold(
          body: Row(
            children: [
              _desktopMenu(admin, constraints.maxWidth > 1180),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
        );
        return scaffold;
      },
    );
  }

  List<Widget> _adminPages() => [
    HomePage(
      isAdmin: true,
      issuers: _issuers,
      onNewIssuer: (id) => _newInvoice(id, 'sponsor'),
      onOpenInvoices: () => _select(2),
      onOpenQuotes: () => _select(3),
      onOpenClients: () => _select(4),
      onOpenIssuers: () => _select(5),
      onOpenRequests: () => _select(1),
      billingRequestsToInvoice: _requestsToInvoice,
      onChooseJon: _chooseJon,
      onNewBright: () => _newInvoice('BN', 'sponsor'),
      onOpenPonencias: () => _select(6),
    ),
    BillingRequestsPage(
      isAdmin: true,
      onBack: () => _select(0),
      onChanged: _refreshCounters,
      onNewQuote: _newQuote,
    ),
    DocumentsPage(
      isQuote: false,
      isAdmin: true,
      refreshToken: _invoiceRefreshToken,
      onBack: () => _select(0),
      onOpenClients: () => _select(4),
      onOpenHistory: null,
    ),
    DocumentsPage(
      isQuote: true,
      isAdmin: true,
      refreshToken: _quoteRefreshToken,
    ),
    ClientsPage(isAdmin: true, onBack: () => _select(0)),
    IssuersPage(onBack: () => _select(0)),
    PonenciasPage(onBack: () => _select(0)),
    UsersRolesPage(onBack: () => _select(0)),
  ];

  List<Widget> _gestionPages() => [
    BillingRequestsPage(
      isAdmin: false,
      onBack: () => _select(0),
      onChanged: _refreshCounters,
      onNewQuote: _newQuote,
    ),
    DocumentsPage(
      isQuote: false,
      isAdmin: false,
      refreshToken: _invoiceRefreshToken,
      onBack: () => _select(0),
    ),
    DocumentsPage(
      isQuote: true,
      isAdmin: false,
      refreshToken: _quoteRefreshToken,
    ),
    ClientsPage(isAdmin: false, onBack: () => _select(0)),
  ];

  Widget _desktopMenu(bool admin, bool wide) {
    return MouseRegion(
      opaque: true,
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => _openDesktopMenu(),
      onHover: (_) => _openDesktopMenu(),
      onExit: (_) => _scheduleDesktopMenuClose(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: _menuOpen ? (wide ? 250 : 220) : 52,
        color: Colors.white,
        child: _menuOpen
            ? Column(
                children: [
                  Expanded(
                    child: NavigationRail(
                      selectedIndex: _selected,
                      onDestinationSelected: _select,
                      extended: true,
                      labelType: NavigationRailLabelType.none,
                      leading: Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 18),
                        child: Row(
                          children: [
                            Image.asset(
                              'assets/bills-logo.png',
                              width: 42,
                              height: 42,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'JHE Billing Hub',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                      destinations: _destinations(admin)
                          .map(
                            (item) => NavigationRailDestination(
                              icon: Icon(item.$1),
                              label: Text(item.$2),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const Divider(height: 1),
                  _notificationMenuAction(),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.logout_outlined),
                    title: const Text('Cerrar sesión'),
                    onTap: _signOut,
                  ),
                  const SizedBox(height: 8),
                ],
              )
            : const Tooltip(
                message: 'Abrir menú',
                child: Center(
                  child: Icon(
                    Icons.chevron_right,
                    size: 22,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _mobileMenu(bool admin) {
    final destinations = _destinations(admin);
    return ColoredBox(
      color: const Color(0xFF142A5C),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Row(
                children: [
                  Image.asset('assets/bills-logo.png', width: 42, height: 42),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'JHE Billing Hub',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final item = destinations[index];
                  final selected = _selected == index;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      selected: selected,
                      selectedTileColor: Colors.white.withValues(alpha: 0.16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      leading: Icon(item.$1, color: Colors.white),
                      title: Text(
                        item.$2,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        _select(index);
                      },
                    ),
                  );
                },
              ),
            ),
            const Divider(color: Color(0xFF52617D), height: 1),
            _notificationMenuAction(dark: true),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white70),
              title: const Text(
                'Cerrar sesión',
                style: TextStyle(color: Colors.white70),
              ),
              onTap: _signOut,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<(IconData, String)> _destinations(bool admin) => admin
      ? const [
          (Icons.home_outlined, 'Inicio'),
          (Icons.assignment_outlined, 'Gestiones administrativas'),
          (Icons.receipt_long_outlined, 'Facturas emitidas'),
          (Icons.request_quote_outlined, 'Presupuestos'),
          (Icons.people_outline, 'Clientes'),
          (Icons.business_outlined, 'Emisores'),
          (Icons.account_tree_outlined, 'Árbol de ponencias'),
          (Icons.manage_accounts_outlined, 'Usuarios y roles'),
        ]
      : const [
          (Icons.assignment_outlined, 'Gestiones administrativas'),
          (Icons.receipt_long_outlined, 'Facturas emitidas'),
          (Icons.request_quote_outlined, 'Presupuestos'),
          (Icons.people_outline, 'Clientes'),
        ];

  Widget _notificationMenuAction({bool dark = false}) => _notificationButton(
    compact: true,
    child: ListTile(
      dense: true,
      leading: _notificationGlyph(color: dark ? Colors.white : null),
      title: Text(
        'Avisos',
        style: TextStyle(color: dark ? Colors.white : null),
      ),
      trailing: _unreadNotifications > 0
          ? Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFB45309),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_unreadNotifications',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : null,
    ),
  );

  Widget _notificationButton({bool compact = false, Widget? child}) =>
      PopupMenuButton<String>(
        tooltip: 'Avisos',
        offset: const Offset(0, 48),
        onOpened: () => unawaited(_refreshCounters()),
        onSelected: (value) => unawaited(_handleNotificationSelection(value)),
        itemBuilder: (menuContext) {
          final available = MediaQuery.sizeOf(menuContext).width - 48;
          final width = compact && available < 380 ? available : 380.0;
          return _notificationMenuItems(width);
        },
        child:
            child ??
            Padding(
              padding: const EdgeInsets.all(12),
              child: _notificationGlyph(),
            ),
      );

  Widget _notificationGlyph({Color? color}) => Stack(
    clipBehavior: Clip.none,
    children: [
      Icon(Icons.notifications_none, color: color),
      if (_unreadNotifications > 0)
        Positioned(
          right: -8,
          top: -8,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFB45309),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$_unreadNotifications',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
    ],
  );

  List<PopupMenuEntry<String>> _notificationMenuItems(double width) {
    final entries = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        enabled: false,
        height: 48,
        child: SizedBox(
          width: width,
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Avisos',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                _unreadNotifications == 0
                    ? 'Todo visto'
                    : '$_unreadNotifications sin leer',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
      const PopupMenuDivider(height: 1),
    ];
    if (_notifications.isEmpty) {
      entries.add(
        PopupMenuItem<String>(
          enabled: false,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text('No hay avisos.')),
            ),
          ),
        ),
      );
      return entries;
    }
    for (final row in _notifications.take(8)) {
      final unread = row['read_at'] == null;
      entries.add(
        PopupMenuItem<String>(
          value: row['id']?.toString() ?? '',
          height: 116,
          child: SizedBox(
            width: width,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Icon(
                    unread
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    size: 20,
                    color: unread
                        ? const Color(0xFF142A5C)
                        : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        row['title']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: unread
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        row['body']?.toString() ?? '',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _notificationTime(row['created_at']),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (unread)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 8, left: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFB45309),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (_unreadNotifications > 0) {
      entries.add(const PopupMenuDivider(height: 1));
      entries.add(
        const PopupMenuItem<String>(
          value: '__mark_all__',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.done_all, size: 18),
              SizedBox(width: 8),
              Text('Marcar todos como vistos'),
            ],
          ),
        ),
      );
    }
    return entries;
  }

  String _notificationTime(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}
