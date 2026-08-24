import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.isAdmin,
    required this.onOpenInvoices,
    required this.onOpenQuotes,
    required this.onOpenClients,
    required this.onOpenIssuers,
    this.onOpenRequests,
    this.billingRequestsToInvoice = 0,
    required this.onChooseJon,
    required this.onNewBright,
    this.onOpenPonencias,
    this.issuers = const [],
    this.onNewIssuer,
  });

  final bool isAdmin;
  final VoidCallback onOpenInvoices;
  final VoidCallback onOpenQuotes;
  final VoidCallback onOpenClients;
  final VoidCallback onOpenIssuers;
  final VoidCallback? onOpenRequests;
  final int billingRequestsToInvoice;
  final VoidCallback onChooseJon;
  final VoidCallback onNewBright;
  final VoidCallback? onOpenPonencias;
  final List<Map<String, dynamic>> issuers;
  final ValueChanged<String>? onNewIssuer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final horizontalPadding = compact ? 16.0 : 28.0;
        final cardWidth = compact
            ? (constraints.maxWidth - horizontalPadding * 2).clamp(0, 446)
            : 446.0;
        return Column(
          children: [
            if (!compact)
              Container(
                height: 130,
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1600),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/bills-logo.png',
                          width: 48,
                          height: 48,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Bills maker',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                _visibleIssuers
                                    .map(
                                      (issuer) =>
                                          issuer['name']?.toString() ??
                                          issuer['id']?.toString() ??
                                          '',
                                    )
                                    .where((name) => name.isNotEmpty)
                                    .join(' · '),
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _role(),
                        const SizedBox(width: 12),
                        _nav(Icons.list, 'Facturas emitidas', onOpenInvoices),
                        if (isAdmin) ...[
                          const SizedBox(width: 10),
                          if (onOpenPonencias != null)
                            _nav(
                              Icons.account_tree_outlined,
                              'Ponencias',
                              onOpenPonencias!,
                            ),
                          if (onOpenPonencias != null)
                            const SizedBox(width: 10),
                          _nav(
                            Icons.edit_note_outlined,
                            'Presupuestos',
                            onOpenQuotes,
                          ),
                          const SizedBox(width: 10),
                          _nav(Icons.people_outline, 'Clientes', onOpenClients),
                          const SizedBox(width: 10),
                          _nav(
                            Icons.settings_outlined,
                            'Emisores',
                            onOpenIssuers,
                          ),
                        ],
                        const SizedBox(width: 10),
                        TextButton.icon(
                          onPressed: () =>
                              Supabase.instance.client.auth.signOut(),
                          icon: const Icon(Icons.logout, size: 20),
                          label: const Text(
                            'Salir',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (!compact) const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: compact ? 24 : 58,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1600),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: _issuerHome(cardWidth.toDouble(), compact),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _issuerHome(double cardWidth, bool compact) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '¿A nombre de quién facturamos?',
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
      ),
      SizedBox(height: compact ? 20 : 30),
      Wrap(
        spacing: 28,
        runSpacing: 28,
        children: [
          for (final issuer in _visibleIssuers)
            _issuerCard(
              Icons.description_outlined,
              issuer['name']?.toString() ??
                  issuer['id']?.toString() ??
                  'Emisor',
              'Numeración: ${issuer['id'] ?? ''}-AAAA-000',
              issuer['id'] == 'JHE'
                  ? 'Ponencia · Complemento · Sponsor'
                  : 'Facturación y gestión de cobros',
              () => _openIssuer(issuer['id']?.toString() ?? ''),
              width: cardWidth,
              height: compact ? 290 : 270,
            ),
        ],
      ),
    ],
  );

  List<Map<String, dynamic>> get _visibleIssuers => issuers.isNotEmpty
      ? issuers
      : const [
          {'id': 'JHE', 'name': 'Jon Hernández'},
          {'id': 'BN', 'name': 'BrightNexus'},
        ];

  void _openIssuer(String id) {
    if (id == 'JHE') return onChooseJon();
    if (id == 'BN') return onNewBright();
    onNewIssuer?.call(id);
  }

  Widget _issuerCard(
    IconData icon,
    String title,
    String line1,
    String line2,
    VoidCallback tap, {
    double height = 270,
    double width = 446,
  }) => SizedBox(
    width: width,
    height: height,
    child: Card(
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 46, color: const Color(0xFF142A5C)),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                line1,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 10),
              Text(
                line2,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _role() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFF142A5C),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      isAdmin ? 'Administrador' : 'Gestión',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _nav(IconData icon, String label, VoidCallback tap) =>
      OutlinedButton.icon(
        onPressed: tap,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
