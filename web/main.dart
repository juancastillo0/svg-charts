import 'dart:convert';
import 'dart:math' as math;
import 'package:bootstrap_dart/bootstrap/checks_radios.dart';
import 'package:bootstrap_dart/bootstrap/icons.dart';
import 'package:universal_html/html.dart' as html;
import 'package:bootstrap_dart/bootstrap/bootstrap_core.dart';
import 'package:bootstrap_dart/bootstrap/form.dart';
import 'package:bootstrap_dart/bootstrap/table.dart';
import 'package:bootstrap_dart/mobx_deact.dart';
import 'package:deact/deact.dart';
import 'package:deact/deact_html52.dart';
import 'package:mobx/mobx.dart';
import 'package:collection/collection.dart';

class PersistenceStore {
  PersistenceStore();

  void set(String key, String value) => html.window.localStorage[key] = value;
  String? get(String key) => html.window.localStorage[key];

  static final ref = Scoped((scope) => PersistenceStore());
}

class RootStore with FromJson {
  final PersistenceStore persistence;

  final charts = ObservableList<ChartInfo>();

  final Observable<ChartInfo?> _selectedChart = Observable(null);
  ChartInfo get selectedChart => _selectedChart.value!;

  RootStore(this.persistence) {
    _initValues();
    autorun(
      (_) {
        persistence.set('RootStore', jsonEncode(toJson()));
      },
      delay: 3000,
    );
  }

  void _initValues() {
    final persisted = persistence.get('RootStore');

    if (persisted != null) {
      try {
        final payload = jsonDecode(persisted) as Map<String, Object?>;
        populateFromJson(payload);
      } catch (_) {}
      if (charts.isNotEmpty) return;
    }
    final c = ChartInfo();
    _selectedChart.value = c;
    charts.add(c);
  }

  static final ref = Scoped(
    (scope) => RootStore(PersistenceStore.ref.get(scope.context)),
  );

  @override
  void populateFromJson(Map<String, Object?> json) {
    charts.addAll((json['charts'] as List).map(ChartInfo.fromJson));
    final chart = json['selectedChart'];
    if (chart is int) {
      _selectedChart.value = charts[chart];
    } else if (charts.isNotEmpty) {
      _selectedChart.value = charts.first;
    }
  }

  @override
  Map<String, Object?> toJson() {
    final selectedChartIndex = charts.indexOf(selectedChart);
    return {
      'charts': charts,
      if (selectedChartIndex != -1) 'selectedChart': selectedChartIndex,
    };
  }
}

mixin FromJson {
  void populateFromJson(Map<String, Object?> json);
  Map<String, Object?> toJson();
}

class ChartInfo with FromJson {
  final title = Observable('A bar chart');
  final description = Observable('This chart shows...');
  final width = Observable(300.0);
  final height = Observable(400.0);
  final maxValue = Observable<double?>(null);
  final showNumbers = Observable(false);
  final showGrid = Observable(false);
  final isLineChart = Observable(false);
  final tableItems = ObservableList<TableItem>(name: 'tableItems');

  ChartInfo() {
    tableItems.addAll([
      TableItem(horizontal: 'label 1', vertical: 10),
      TableItem(horizontal: 'label 2', vertical: 6, color: 'cf1717'),
    ]);
  }

  static ChartInfo fromJson(dynamic json) {
    final v = ChartInfo();
    v.populateFromJson(json as Map<String, Object?>);
    return v;
  }

  @override
  void populateFromJson(Map<String, Object?> json) {
    if (json['title'] is String) {
      title.value = json['title'] as String;
    }
    if (json['description'] is String) {
      description.value = json['description'] as String;
    }
    if (json['width'] is double) {
      width.value = json['width'] as double;
    }
    if (json['height'] is double) {
      height.value = json['height'] as double;
    }
    if (json['maxValue'] is double) {
      maxValue.value = json['maxValue'] as double;
    }
    if (json['showNumbers'] is bool) {
      showNumbers.value = json['showNumbers'] as bool;
    }
    if (json['showGrid'] is bool) {
      showGrid.value = json['showGrid'] as bool;
    }
    if (json['isLineChart'] is bool) {
      isLineChart.value = json['isLineChart'] as bool;
    }
    if (json['tableItems'] is List) {
      tableItems.clear();
      tableItems.addAll((json['tableItems'] as List).map(TableItem.fromJson));
    }
  }

  @override
  Map<String, Object?> toJson() => {
        'title': title.value,
        'description': description.value,
        'width': width.value,
        'height': height.value,
        'maxValue': maxValue.value,
        'showNumbers': showNumbers.value,
        'showGrid': showGrid.value,
        'isLineChart': isLineChart.value,
        'tableItems': tableItems,
      };

  late final allIncreasing = Computed(() {
    int max = -1 * 10 ^ 10;
    return tableItems.every((element) {
      final v = int.tryParse(element.horizontal.value);
      if (v == null) return true;
      return v == null;
    });
  });

  late final allLabelsAreNumbers = Computed(() {
    return tableItems.every(
      (element) => double.tryParse(element.horizontal.value) != null,
    );
  });

  late final sortedByLabel = Computed(() {
    if (!allLabelsAreNumbers.value) return tableItems;
    return [...tableItems]..sort(
        (a, b) => (double.parse(b.horizontal.value) -
                double.parse(a.horizontal.value))
            .round(),
      );
  });

  late final maxLabelLength = Computed<int>(() {
    final max =
        tableItems.fold<int>(-1 * math.pow(10, 8).toInt(), (max, element) {
      final v = element.horizontal.value.length;
      return v > max ? v : max;
    });
    return max == 0 ? 100 : max;
  });

  late final maxAbsoluteValue = Computed<double>(() {
    final max = tableItems.fold<double>(-1.0 * math.pow(10, 8), (max, element) {
      final v = element.vertical.value.abs();
      return v > max ? v : max;
    });
    final _max = max == 0 ? 100.0 : max;
    final configured = maxValue.value;
    return configured == null
        ? _max
        : configured > _max
            ? configured
            : _max;
  });

  late final svgString = Computed(() {
    final String mainContent;

    if (!isLineChart.value) {
      double y = 32;
      const deltaY = 25.0;
      final xRect = maxLabelLength.value * 11;
      final maxWidth = width.value - xRect;

      mainContent = tableItems.map((element) => '''
<g class="bar">
  <text x="0" y="${8 + (y += deltaY)}" dy=".35em">${element.horizontal.value}</text>
  <rect x="$xRect" y="$y" width="${element.vertical.value / maxAbsoluteValue.value * maxWidth}"
   fill="#${element.color.value}" height="19"></rect>
</g>
''').join('\n');
    } else {
      double x = 0;
      final maxHeight = height.value - 65;
      final deltaX =
          tableItems.length == 1 ? 0 : width.value / (tableItems.length - 1);

      mainContent = '''
<polyline
     fill="none"
     stroke="#0074d9"
     stroke-width="3"
     points="
${sortedByLabel.value.map((element) {
        final _x = x;
        x += deltaX;
        return '$_x,${height.value - element.vertical.value / maxAbsoluteValue.value * maxHeight}';
      }).join('\n')}
/">''';
    }

    return '''
<svg class="chart" width="${width.value}" height="${height.value}" aria-labelledby="title desc" role="img">
<text x="0" y="16" id="title">${title.value}</text>
<text x="0" y="36" id="desc">${description.value}</text>

<!-- <circle r="25" cx="50" cy="50" class="pie"/> --->

$mainContent

$_svgStyle
</svg>
''';
  });
}

DeactNode _numberInput({
  required String id,
  required Observable<double> observable,
  String? title,
  String? placeholder,
}) {
  return fc(
    (ctx) => input(
      className: formControlClass(size: BSize.sm),
      type: 'number',
      title: title,
      placeholder: placeholder,
      id: id,
      value: observable.value.toString(),
      oninput: (e) {
        final v = double.tryParse(
          (e.target! as html.InputElement).value!,
        );
        if (v == null) return;
        observable.value = v;
      },
    ),
  );
}

void main() {
  mainContext.config = mainContext.config.clone(
    writePolicy: ReactiveWritePolicy.never,
  );
  deact(
    '#output',
    (_) {
      return fc((ctx) {
        final store = RootStore.ref.get(ctx);
        final chart = store.selectedChart;

        final svgDivRef = ctx.hookRef<html.Element?>(() => null);
        ctx.hookEffect(() {
          return autorun((_) {
            svgDivRef.value!.setInnerHtml(
              chart.svgString.value,
              validator: html.NodeValidatorBuilder()..allowSvg(),
            );
          });
        });

        return div(
          children: [
            ChartForm(),
            MainTable(),
            button(
              className: btn() + ' mb-3',
              onclick: (_) => html.window.navigator.clipboard
                  ?.writeText(chart.svgString.value),
              children: [
                icon(BIcon.clipboard),
                el(
                  'span',
                  attributes: {'style': 'padding-left:10px;'},
                  children: [
                    txt('Copy SVG'),
                  ],
                ),
              ],
            ),
            el('div', ref: svgDivRef),
          ],
        );
      });
    },
    wrappers: const [mobxWrapper],
  );
}

class TableItem with FromJson {
  final Observable<String> horizontal;
  final Observable<double> vertical;
  final Observable<String> color;

  TableItem({
    required String horizontal,
    required double vertical,
    String color = '000000',
  })  : horizontal = Observable(horizontal),
        vertical = Observable(vertical),
        color = Observable(color);

  static TableItem fromJson(dynamic json) {
    final v = TableItem(horizontal: '', vertical: 10);
    v.populateFromJson(json as Map<String, Object?>);
    return v;
  }

  @override
  void populateFromJson(Map<String, Object?> json) {
    if (json['horizontal'] is String) {
      horizontal.value = json['horizontal'] as String;
    }
    if (json['vertical'] is double) {
      vertical.value = json['vertical'] as double;
    }
    if (json['color'] is String) {
      color.value = json['color'] as String;
    }
  }

  @override
  Map<String, Object?> toJson() => {
        'horizontal': horizontal.value,
        'vertical': vertical.value,
        'color': color.value,
      };
}

class ChartForm extends ComponentNode {
  ChartForm({Object? key}) : super(key: key);

  @override
  DeactNode render(ComponentContext ctx) {
    final store = RootStore.ref.get(ctx);
    final chart = store.selectedChart;

    return div(
      className: 'mb-2',
      style: flexCenter(column: true),
      children: [
        div(
          className: 'mb-2',
          style: flexCenter(),
          children: [
            labeledInput(
              wrapperDivClass: 'my-2 align-self-start ps-3',
              label: txt('Title'),
              id: 'chart-title',
              divClass: 'row display-self-start',
              // colClasses: colClasses,
              input: input(
                className: formControlClass(size: BSize.sm),
                placeholder: 'A bar chart',
                type: 'text',
                id: 'chart-title',
                value: chart.title.value,
                oninput: (e) =>
                    chart.title.value = (e.target! as html.InputElement).value!,
              ),
            ),
            labeledInput(
              wrapperDivClass: 'my-2 px-3',
              label: txt('Description'),
              id: 'chart-description',
              divClass: 'row',
              // colClasses: colClasses,
              input: textarea(
                className: formControlClass(size: BSize.sm) + ' mx-3',
                placeholder: 'A bar chart showing information',
                style: 'height:100px;',
                id: 'chart-description',
                oninput: (e) => chart.description.value =
                    (e.target as html.TextAreaElement).value!,
                children: [txt(chart.description.value)],
              ),
            ),
          ],
        ),
        div(
          className: 'mb-2',
          style: flexCenter(),
          children: [
            div(className: 'pl-3', children: [
              _numberInput(
                id: 'chart-width',
                observable: chart.width,
                title: 'Width',
              ),
            ]),
            div(className: 'px-3', children: [
              _numberInput(
                id: 'chart-height',
                observable: chart.height,
                title: 'Height',
              ),
            ]),
            check(
              label: span(children: [txt('Show Grid')]),
              inline: true,
              name: 'showGrid',
              checked: chart.showGrid.value,
              type: CheckType.switch_,
              // labelStyle: 'width:120px;',
              id: 'show-grid',
              onChange: (checked) => chart.showGrid.value = checked,
            ),
            check(
              label: txt('Show Numbers'),
              inline: true,
              name: 'showNumbers',
              checked: chart.showNumbers.value,
              type: CheckType.switch_,
              // labelStyle: 'width:120px;',
              id: 'show-numbers',
              onChange: (checked) => chart.showNumbers.value = checked,
            ),
            check(
              label: span(children: [txt('Line Chart')]),
              inline: true,
              name: 'isLineChart',
              checked: chart.isLineChart.value,
              type: CheckType.switch_,
              // labelStyle: 'width:120px;',
              id: 'line-chart',
              onChange: (checked) => chart.isLineChart.value = checked,
            ),
          ],
        ),
      ],
    );
  }
}

class MainTable extends ComponentNode {
  MainTable({Object? key}) : super(key: key);

  @override
  DeactNode render(ComponentContext ctx) {
    final tableItems = RootStore.ref.get(ctx).selectedChart.tableItems;

    return table(
      className: tableClass(
        // hover: hover.value,
        bordered: true,
        // borderless: borderless.value,
        captionTop: true,
        // striped: true,
        small: true,
        // color: color.value,
        // align: align.value,
        // scrollHorizontal: scrollHorizontal.value,
      ),
      children: [
        caption(children: [txt('Chart Data')]),
        thead(
          children: [
            tr(
              children: [
                th(scope: 'col', children: [txt('#')]),
                th(scope: 'col', children: [txt('Label')]),
                th(scope: 'col', children: [txt('Value')]),
                th(scope: 'col', children: [txt('Color')]),
              ],
            ),
          ],
        ),
        tbody(
          children: [
            ...tableItems.mapIndexed(
              (index, item) => tr(
                children: [
                  th(scope: 'row', children: [txt('${index + 1}')]),
                  // colspan: (item.last != null ? 1 : 2).toString(),
                  td(children: [
                    fc(
                      (ctx) => input(
                        className: formControlClass(size: BSize.sm),
                        type: 'text',
                        // placeholder: 'Placeholder Invalid',
                        id: 'table-label-$index',
                        value: item.horizontal.value,
                        oninput: (e) => item.horizontal.value =
                            (e.target! as html.InputElement).value!,
                      ),
                    ),
                  ]),
                  td(children: [
                    fc(
                      (ctx) => input(
                        className: formControlClass(size: BSize.sm),
                        type: 'number',
                        // placeholder: 'Placeholder Invalid',
                        id: 'table-value-$index',
                        value: item.vertical.value.toString(),
                        oninput: (e) {
                          final v = double.tryParse(
                            (e.target! as html.InputElement).value!,
                          );
                          if (v == null) return;
                          item.vertical.value = v;
                        },
                      ),
                    ),
                  ]),
                  td(children: [
                    fc(
                      (ctx) => input(
                        className: formControlClass(size: BSize.sm),
                        type: 'color',
                        // placeholder: 'Placeholder Invalid',
                        id: 'table-color-$index',
                        value: '#${item.color.value}',
                        oninput: (e) {
                          item.color.value = (e.target! as html.InputElement)
                              .value!
                              .substring(1);
                        },
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
        // if (showFooter.value)
        tfoot(
          children: [
            tr(
              children: Iterable.generate(
                4,
                (index) => td(
                  children: [
                    if (index == 0)
                      button(
                        className: btn(),
                        onclick: (_) {
                          tableItems.add(
                            TableItem(
                              horizontal: 'label ${tableItems.length + 1}',
                              vertical: 5,
                            ),
                          );
                        },
                        children: [txt('Add Data Point')],
                      )
                    else
                      txt('Footer $index'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

const _svgStyle = '''
<style>
  .bar {
    height: 21px;
    transition: fill .3s ease;
    cursor: pointer;
    font-size: 16px;
    font-family: monospace; /*Helvetica, sans-serif*/
  }
  .bar text {
    color: black;
  }
  .bar:hover,
  .bar:focus {
    fill: black;
  }
  .bar:hover text,
  .bar:focus text {
    fill: red;
  }
</style>
''';
