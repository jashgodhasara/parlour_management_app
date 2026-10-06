import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/customers/presentation/customer_list_screen.dart';
import '../../features/customers/presentation/customer_detail_screen.dart';
import '../../features/customers/presentation/customer_edit_screen.dart';
import '../../features/appointments/presentation/appointment_list_screen.dart';
import '../../features/appointments/presentation/appointment_form_screen.dart';
import '../../features/billing/presentation/billing_screen.dart';
import '../../features/billing/presentation/bill_detail_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/services/presentation/service_catalog_screen.dart';
import '../../features/services/presentation/service_form_screen.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            ScaffoldWithBottomNav(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/customers',
            builder: (context, state) => const CustomerListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const CustomerEditScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => CustomerDetailScreen(
                    customerId: state.pathParameters['id']!),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => CustomerEditScreen(
                        customerId: state.pathParameters['id']),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/appointments',
            builder: (context, state) => const AppointmentListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const AppointmentFormScreen(),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (context, state) => AppointmentFormScreen(
                    appointmentId: state.pathParameters['id']),
              ),
            ],
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/billing/new',
        builder: (context, state) => BillingScreen(
            customerId: state.uri.queryParameters['customerId']),
      ),
      GoRoute(
        path: '/billing/:id',
        builder: (context, state) =>
            BillDetailScreen(billId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'services',
            builder: (context, state) => const ServiceCatalogScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const ServiceFormScreen(),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (context, state) => ServiceFormScreen(
                    serviceId: state.pathParameters['id']),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class ScaffoldWithBottomNav extends StatelessWidget {
  final Widget child;

  const ScaffoldWithBottomNav({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (index) =>
            _onDestinationSelected(context, index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Customers'),
          NavigationDestination(
              icon: Icon(Icons.calendar_today), label: 'Appointments'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart), label: 'Reports'),
        ],
      ),
    );
  }

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/customers')) return 1;
    if (location.startsWith('/appointments')) return 2;
    if (location.startsWith('/reports')) return 3;
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/customers');
        break;
      case 2:
        context.go('/appointments');
        break;
      case 3:
        context.go('/reports');
        break;
    }
  }
}
