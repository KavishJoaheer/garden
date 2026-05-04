import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:gardnx_app/features/calendar/domain/models/planting_event.dart';
import 'package:gardnx_app/features/calendar/presentation/providers/calendar_provider.dart';
import 'package:gardnx_app/features/calendar/presentation/widgets/event_indicator.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final selectedDay = ref.watch(selectedCalendarDayProvider);
    final eventsByDay = ref.watch(eventsByDayProvider);
    final gardenEventsAsync = ref.watch(gardenEventsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    List<PlantingEvent> getEventsForDay(DateTime day) {
      return eventsByDay[DateTime(day.year, day.month, day.day)] ?? [];
    }

    final selectedEvents = getEventsForDay(selectedDay);

    return Scaffold(
      appBar: AppBar(title: const Text('Planting Calendar')),
      body: Column(
        children: [
          // Calendar
          Card(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            clipBehavior: Clip.antiAlias,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: TableCalendar<PlantingEvent>(
              firstDay: DateTime(DateTime.now().year - 1, 1, 1),
              lastDay: DateTime(DateTime.now().year + 2, 12, 31),
              focusedDay: selectedDay,
              calendarFormat: _calendarFormat,
              selectedDayPredicate: (day) => isSameDay(selectedDay, day),
              eventLoader: getEventsForDay,
              onDaySelected: (selected, focused) {
                ref.read(selectedCalendarDayProvider.notifier).state =
                    selected;
              },
              onFormatChanged: (format) {
                setState(() => _calendarFormat = format);
              },
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                todayTextStyle: TextStyle(color: colorScheme.primary),
                selectedDecoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle:
                    TextStyle(color: colorScheme.onPrimary),
                markerDecoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                markersMaxCount: 4,
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: EventIndicatorRow(
                      events: events,
                      dotSize: 5,
                    ),
                  );
                },
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: true,
                titleCentered: true,
                formatButtonShowsNext: false,
              ),
            ),
          ),

          // Event legend
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: PlantingEventType.values
                  .where((t) =>
                      t != PlantingEventType.general &&
                      t != PlantingEventType.water &&
                      t != PlantingEventType.fertilize)
                  .map((t) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            EventIndicator(eventType: t, size: 8),
                            const SizedBox(width: 4),
                            Text(t.label,
                                style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),

          const Divider(height: 1),

          // Events for selected day
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  _formatSelectedDate(selectedDay),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (selectedEvents.isNotEmpty)
                  Text(
                    '${selectedEvents.length} event${selectedEvents.length != 1 ? 's' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),

          Expanded(
            child: gardenEventsAsync.when(
              data: (_) {
                if (selectedEvents.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_available,
                          size: 48,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No events today',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                  itemCount: selectedEvents.length,
                  itemBuilder: (context, index) {
                    return _EventListTile(event: selectedEvents[index]);
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: TextStyle(color: colorScheme.error)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSelectedDate(DateTime date) {
    const days = [
      '', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    ];
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[date.weekday]}, ${date.day} ${months[date.month]} ${date.year}';
  }
}

class _EventListTile extends ConsumerWidget {
  final PlantingEvent event;

  const _EventListTile({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = event.eventType.color;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () async {
          final err = await ref
              .read(gardenEventsProvider.notifier)
              .toggleEventCompletion(event);
          if (err != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not update event: $err'),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        },
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(event.eventType.icon, color: color, size: 20),
        ),
        title: Text(
          '${event.eventType.label}: ${event.plantName}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            decoration:
                event.isCompleted ? TextDecoration.lineThrough : null,
            color: event.isCompleted
                ? colorScheme.onSurfaceVariant
                : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event.bedName != null && event.bedName!.isNotEmpty)
              Text(
                event.bedName!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (event.notes != null)
              Text(event.notes!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  )),
          ],
        ),
        trailing: event.isCompleted
            ? const Icon(Icons.check_circle, color: Colors.green, size: 24)
            : Icon(Icons.radio_button_unchecked,
                color: colorScheme.onSurfaceVariant, size: 24),
      ),
    );
  }
}

