import 'package:bills_maker/app.dart';
import 'package:bills_maker/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra el estado de configuración sin claves', (tester) async {
    await tester.pumpWidget(const BillsMakerApp());
    expect(find.text('Bills Maker'), findsOneWidget);
    expect(find.textContaining('configuración pública'), findsOneWidget);
  });

  testWidgets('administración solo puede entrar en facturas emitidas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1900, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            isAdmin: false,
            onOpenInvoices: () {},
            onOpenQuotes: () {},
            onOpenClients: () {},
            onOpenIssuers: () {},
            onChooseJon: () {},
            onNewBright: () {},
          ),
        ),
      ),
    );

    expect(find.text('Gestión'), findsOneWidget);
    expect(find.text('Facturas emitidas'), findsOneWidget);
    expect(find.text('Presupuestos'), findsNothing);
    expect(find.text('Clientes'), findsNothing);
    expect(find.text('Emisores'), findsNothing);
  });

  testWidgets('inicio se adapta a una pantalla Android estrecha', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            isAdmin: true,
            onOpenInvoices: () {},
            onOpenQuotes: () {},
            onOpenClients: () {},
            onOpenIssuers: () {},
            onChooseJon: () {},
            onNewBright: () {},
          ),
        ),
      ),
    );

    expect(find.text('¿A nombre de quién facturamos?'), findsOneWidget);
    expect(find.text('Jon Hernández'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
