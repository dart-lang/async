import 'package:async/async.dart';
import 'package:test/test.dart';

void main() {
  group('test requiredValue', () {
    test(
      'return value when result is value',
      () {
        final result = Result.value(10);
        expect(result.requireValue, 10);
      },
    );

    test(
      'return nullable value when result is nullable value',
      () {
        final result = Result<int?>.value(null);
        expect(result.requireValue, null);
      },
    );

    test(
      'throw exception when result is error',
      () async {
        final result = Result.error('error');
        expect(() => result.requireValue, throwsA(anything));
      },
    );

    test(
      'throw the corresponding and stacktrace exception when result is error',
      () async {
        final error = Exception();
        final stacktrace = StackTrace.current;
        final result = Result.error(error,stacktrace);

        expect(
          () => result.requireValue,
          throwsA(
            predicate((err) {
              return err == error;
            }),
          ),
        );
      },
    );
  });

  group('test valueOrNull', () {
    test('return null when result is error', (){
      final result = Result.error('error');
      expect(result.valueOrNull, null);
    });

    test('return value when result is value ', (){
      final result = Result.value(10);
      expect(result.valueOrNull, 10);
    });
    
    test('return nullable value when result is nullable value ', (){
      final result = Result<int?>.value(null);
      expect(result.valueOrNull, null);
    });
    
  });

}
