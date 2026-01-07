# Adding New Features

This guide walks you through the process of adding a new feature to the Audiobook Flutter app.

## Feature Development Workflow

### 1. Planning Phase

#### Create Feature Branch
```bash
# Update main branch
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/feature-name

# Keep branch up to date
git rebase main
```

#### Design Document
Create feature documentation early:

```bash
mkdir -p docs/features/feature-name
cp docs/features/FEATURE_TEMPLATE.md docs/features/feature-name/README.md
```

Update the template with:
- Feature overview and motivation
- Architecture and design decisions
- Integration points with existing code
- Testing strategy

### 2. Implementation Phase

#### Project Structure

```
lib/
├── ui/screens/
│   └── feature_name_screen.dart        # Main screen
├── ui/widgets/
│   └── feature_name_widgets.dart       # Reusable components
├── app/
│   └── feature_name_providers.dart     # Riverpod providers
└── features/
    └── feature_name/
        ├── controller.dart             # Business logic
        ├── models.dart                 # Data models
        └── service.dart                # External services
```

#### Creating Screens

```dart
// lib/ui/screens/my_feature_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MyFeatureScreen extends ConsumerWidget {
  const MyFeatureScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch providers for reactive updates
    final state = ref.watch(myFeatureProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('My Feature')),
      body: state.when(
        loading: () => const CircularProgressIndicator(),
        error: (err, st) => Text('Error: $err'),
        data: (data) => _buildContent(context, data),
      ),
    );
  }

  Widget _buildContent(BuildContext context, MyFeatureData data) {
    return ListView(
      children: [
        // Your content here
      ],
    );
  }
}
```

#### Creating Providers

```dart
// lib/app/my_feature_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Data model
final myFeatureProvider = 
    AsyncNotifierProvider<MyFeatureController, MyFeatureState>(() {
  return MyFeatureController();
});

// Controller for business logic
class MyFeatureController extends AsyncNotifier<MyFeatureState> {
  @override
  FutureOr<MyFeatureState> build() async {
    // Initialize state
    return const MyFeatureState();
  }

  Future<void> myAction(String param) async {
    // Business logic
  }
}

// State class
class MyFeatureState {
  const MyFeatureState({
    this.isLoading = false,
    this.data = const [],
    this.error,
  });

  final bool isLoading;
  final List<String> data;
  final String? error;

  MyFeatureState copyWith({
    bool? isLoading,
    List<String>? data,
    String? error,
  }) {
    return MyFeatureState(
      isLoading: isLoading ?? this.isLoading,
      data: data ?? this.data,
      error: error ?? this.error,
    );
  }
}
```

#### Adding to Navigation

Update `lib/main.dart` to add routes:

```dart
GoRoute(
  path: '/my-feature',
  builder: (context, state) => const MyFeatureScreen(),
),
```

### 3. Testing Phase

#### Unit Tests

```dart
// test/my_feature_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MyFeature', () {
    test('should initialize state correctly', () {
      // Test initialization
    });

    test('should handle user actions', () {
      // Test business logic
    });

    test('should handle errors gracefully', () {
      // Test error handling
    });
  });
}
```

#### Widget Tests

```dart
// test/my_feature_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('MyFeatureScreen', () {
    testWidgets('renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MyFeatureScreen(),
          ),
        ),
      );

      expect(find.text('My Feature'), findsOneWidget);
    });

    testWidgets('responds to user interactions', (WidgetTester tester) async {
      // Test widget interactions
    });
  });
}
```

#### Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/my_feature_test.dart

# Run with coverage
flutter test --coverage

# View coverage report
open coverage/lcov-report/index.html  # macOS
xdg-open coverage/lcov-report/index.html  # Linux
```

### 4. Code Quality

#### Static Analysis

```bash
# Analyze code
flutter analyze

# Format code
flutter format lib/ test/

# Fix common issues
dart fix --apply
```

#### Code Review Checklist

- [ ] Code follows project style guide
- [ ] No analysis warnings or errors
- [ ] Tests added and passing
- [ ] Documentation updated
- [ ] Performance considered
- [ ] Error handling implemented
- [ ] Backward compatibility maintained

### 5. Documentation

#### Update Feature Documentation

Fill in the feature template created in Planning Phase:

```markdown
# [Feature Name]

## Overview
[Description]

## Motivation
[Why it was needed]

## Design
[Architecture and decisions]

## Implementation
[What was changed]

## Testing
[Test strategy and coverage]

## Known Limitations
[Any limitations]
```

#### Update Main README

Add entry to features list in root README.md

#### Add Code Comments

```dart
/// Explains what this method does and why.
/// 
/// Parameters:
///   - param1: What param1 does
/// 
/// Returns:
///   The result of the operation
/// 
/// Throws:
///   - [MyException] when something goes wrong
Future<Result> myMethod(String param1) async {
  // Implementation
}
```

### 6. Integration Testing

#### Setup Integration Tests

```bash
# Create integration test
touch integration_test/my_feature_test.dart
```

#### Write Integration Test

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('MyFeature Integration Tests', () {
    testWidgets('complete user flow', (WidgetTester tester) async {
      // Launch app
      app.main();
      await tester.pumpAndSettle();

      // Test complete flow
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('Success'), findsOneWidget);
    });
  });
}
```

#### Run Integration Tests

```bash
# Run on specific device
flutter test integration_test/my_feature_test.dart -d device_id

# Run on all devices
flutter test integration_test/
```

### 7. Performance

#### Profile Feature

```bash
# Run with profiling
flutter run --profile

# Use DevTools for profiling
flutter pub global run devtools

# Check performance in DevTools UI
```

#### Performance Checklist

- [ ] No unnecessary rebuilds
- [ ] Efficient state management
- [ ] Appropriate use of `const` constructors
- [ ] No memory leaks
- [ ] Async operations properly handled
- [ ] UI responds within 16ms for 60fps

### 8. Submission & Review

#### Prepare PR

```bash
# Ensure branch is up to date
git fetch origin
git rebase origin/main

# Push to remote
git push origin feature/feature-name
```

#### PR Description Template

```markdown
## Description
Brief description of what this feature does.

## Type of Change
- [ ] New feature
- [ ] Bug fix
- [ ] Breaking change
- [ ] Documentation update

## Motivation and Context
Why is this change needed?

## Testing Done
- [ ] Unit tests
- [ ] Widget tests
- [ ] Integration tests
- [ ] Manual testing

## Screenshots
[If applicable]

## Checklist
- [ ] Code follows style guidelines
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No breaking changes
- [ ] Performance considered

## Related Issues
Closes #123
```

#### Review Process

1. Create Pull Request
2. Wait for CI/CD checks to pass
3. Address review comments
4. Get approval from at least one reviewer
5. Merge to develop
6. Merge to main when ready for release

## Best Practices

### State Management

```dart
// Good: Use Riverpod for global state
final myStateProvider = StateNotifierProvider<MyController, MyState>(...);

// Avoid: Direct state manipulation
// Bad: _state = newState; // Use Riverpod instead
```

### Async Operations

```dart
// Good: Handle loading, error, and success states
final dataProvider = FutureProvider<Data>((ref) async {
  return fetchData();
});

// In UI:
data.when(
  loading: () => Loading(),
  error: (err, st) => Error(err),
  data: (data) => Content(data),
)

// Avoid: Not handling loading/error states
```

### Widget Organization

```dart
// Good: Break into smaller widgets
class MyFeatureScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _Header(),
        _Content(),
        _Footer(),
      ],
    );
  }

  Widget _Header() => ...
  Widget _Content() => ...
  Widget _Footer() => ...
}

// Avoid: Single huge build method
```

## Common Patterns

### Feature with External API Call

See [Guides/API Integration](./api-integration.md)

### Feature with Local Database

See [Guides/Local Storage](./local-storage.md)

### Feature with Complex UI

See [Guides/Advanced Widgets](./advanced-widgets.md)

## Troubleshooting

### Common Issues

#### "Provider not found"
- Ensure provider is imported
- Check provider name spelling
- Verify provider is defined before use

#### "State not updating"
- Use `ref.watch()` not `ref.read()` for reactive updates
- Ensure state changes are immutable
- Check that notifier emits new state

#### "Widget not rebuilding"
- Verify using `ref.watch()` in widget
- Check that watched provider actually changes
- Look for `const` constructors preventing rebuilds

## Related Documentation

- [Architecture Guide](../ARCHITECTURE.md)
- [Testing Strategy](./testing.md)
- [Code Style Guide](./style-guide.md)
- [Project Structure](./project-structure.md)

---

**Last Updated**: January 7, 2026
