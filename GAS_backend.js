/*******************************************************
 * Juanniao POS Backend（統一版骨架＋相容舊版欄位＋fallback 分類）
 *******************************************************/

// 取得目前這支 Script 綁定的試算表
function getPOSSpreadsheet_() {
  return SpreadsheetApp.getActiveSpreadsheet();
}

// 統一 JSON 回傳
function jsonResponse_(obj, statusCode) {
  if (!statusCode) statusCode = 200;
  var output = ContentService.createTextOutput(JSON.stringify(obj));
  output.setMimeType(ContentService.MimeType.JSON);
  return output;
}

// 初始化資料表
function initPOSDatabase() {
  var ss = getPOSSpreadsheet_();

  function ensureSheet_(name, headers) {
    var sheet = ss.getSheetByName(name);
    if (!sheet) {
      sheet = ss.insertSheet(name);
      if (headers && headers.length) {
        sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
        sheet.setFrozenRows(1);
      }
    }
    return sheet;
  }

  // Categories
  ensureSheet_('Categories', [
    'CategoryId',
    'Name',
    'SortOrder',
    'IsActive'
  ]);

  // Items
  ensureSheet_('Items', [
    'ItemId',
    'CategoryId',
    'Name',
    'Price',
    'IsActive',
    'AllowOat',
    'OptionsJSON',
    'AddOnsJSON'
  ]);

  // CategoryAddOns
  ensureSheet_('CategoryAddOns', [
    'AddOnId',
    'CategoryId',
    'Name',
    'Price',
    'IsActive'
  ]);

  // Orders
  ensureSheet_('Orders', [
    'OrderId',
    'CreatedAt',
    'TableName',
    'ItemsJSON',
    'Amount',
    'PayMethod',
    'Status',
    'Note',
    'LinePayTransactionId',
    'ClosedFlag'
  ]);

  // CloseShift
  ensureSheet_('CloseShift', [
    'Date',
    'TotalAmount',
    'Cash',
    'Card',
    'LinePay',
    'TapPay',
    'OrderCount',
    'CreatedAt'
  ]);

  // Blacklist
  ensureSheet_('Blacklist', [
    'Phone',
    'AddedAt'
  ]);

  // Reservations
  ensureSheet_('Reservations', [
    'ReservationId',
    'Date',
    'Time',
    'Name',
    'Title',
    'Phone',
    'Adults',
    'Children',
    'Note',
    'Status',
    'CreatedAt'
  ]);

  return jsonResponse_({ ok: true, message: 'initPOSDatabase done' });
}

// 一次性：塞入 11 個分類（只在 Categories 只有表頭時才會動）
function seedJuanniaoCategories_() {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Categories');
  if (!sheet) {
    throw new Error('Categories sheet not found，請先跑 initPOSDatabase()');
  }

  var lastRow = sheet.getLastRow();
  if (lastRow > 1) {
    Logger.log('Categories already has data, skip seeding.');
    return;
  }

  var rows = [
    ['CAT001', '義式咖啡', 1, true],
    ['CAT002', '手沖咖啡', 2, true],
    ['CAT003', 'SOE', 3, true],
    ['CAT004', '茶類', 4, true],
    ['CAT005', '牛奶類', 5, true],
    ['CAT006', '冰滴', 6, true],
    ['CAT007', '甜點鹹食', 7, true],
    ['CAT008', '酒類', 8, true],
    ['CAT009', '咖啡豆', 9, true],
    ['CAT010', '配件', 10, true],
    ['CAT011', '整模蛋糕', 11, true]
  ];

  sheet.getRange(2, 1, rows.length, rows[0].length).setValues(rows);
  Logger.log('Juanniao default categories seeded.');
}

/*******************************************************
 * API 入口：doGet / doPost
 *******************************************************/

function doGet(e) {
  // 手機網頁介面
  if (e && e.parameter && e.parameter.view === 'mobile') {
    return mobilePage_();
  }

  var action = (e && e.parameter && e.parameter.action) || 'getMenu';

  if (action === 'getMenu') {
    return jsonResponse_(getMenu_());
  }

  if (action === 'getReservations') {
    return jsonResponse_(getReservations_());
  }

  if (action === 'getBlacklist') {
    return jsonResponse_(getBlacklist_());
  }

  if (action === 'getCakeOrders') {
    var from = (e && e.parameter && e.parameter.from) || '';
    var to   = (e && e.parameter && e.parameter.to)   || '';
    return jsonResponse_(getCakeOrders_(from, to));
  }

  if (action === 'debugMenuRaw') {
    return jsonResponse_(debugMenuRaw_());
  }

  // 後台管理（分類 + 品項 + 附加選項）
  if (action === 'getAdminMenu') {
    return jsonResponse_(getAdminMenu_());
  }

  // 今日訂單查詢
  if (action === 'getTodayOrders') {
    return jsonResponse_(getTodayOrders_());
  }

  // 營業中即時總覽（含 PENDING）
  if (action === 'getLiveBusinessSummary') {
    return jsonResponse_(getLiveBusinessSummary_());
  }

  // 正式關帳總覽（只含 PAID）
  if (action === 'getCloseShiftSummary') {
    return jsonResponse_(getCloseShiftSummary_());
  }

  return jsonResponse_({
    error: 'Unknown GET action: ' + action,
    knownActions: [
      'getMenu',
      'debugMenuRaw',
      'getAdminMenu',
      'getTodayOrders',
      'getLiveBusinessSummary',
      'getCloseShiftSummary'
    ]
  });
}

function doPost(e) {
  if (!e || !e.postData || !e.postData.contents) {
    return jsonResponse_(
      { error: 'Empty body (doPost called without HTTP POST)' },
      400
    );
  }

  var raw = e.postData.contents;
  var data;
  try {
    data = JSON.parse(raw);
  } catch (err) {
    return jsonResponse_(
      { error: 'Invalid JSON', detail: String(err) },
      400
    );
  }

  // ★ action 優先用 body，其次才看 URL ?action=
  var action =
    (data && data.action) ||
    (e && e.parameter && e.parameter.action) ||
    '';

  switch (action) {
    case 'initPOSDatabase':
      return initPOSDatabase();

    case 'getMenu':
      return jsonResponse_(getMenu_());

    case 'createOrder':
      return jsonResponse_(createOrderFromDevice_(data));

    case 'updateOrderStatus':
      return jsonResponse_(updateOrderStatus_(data));

    case 'dailyClose':
      return jsonResponse_(dailyClose_(data));

    case 'linePayOfflinePay':
      return jsonResponse_(linePayOfflinePay_(data));

    case 'saveAdminMenu':
      return jsonResponse_(saveAdminMenu_(data));

    case 'deleteOrder':
      return jsonResponse_(deleteOrder_(data));

    case 'updateOrder':
      return jsonResponse_(updateOrder_(data));

    case 'closeShift':
      return jsonResponse_(closeShift_(data));

    case 'archiveCurrentMonth':
      return jsonResponse_(archiveCurrentMonthOrders_(data));

    case 'createReservation':
      return jsonResponse_(createReservation_(data));

    case 'addToBlacklist':
      return jsonResponse_(addToBlacklist_(data));

    case 'updateReservation':
      return jsonResponse_(updateReservation_(data));

    case 'deleteReservation':
      return jsonResponse_(deleteReservation_(data));

    case 'moveTable':
      return jsonResponse_(moveTable_(data));

    case 'updateOrderPaymentStatus':
      return jsonResponse_(updateOrderPaymentStatus_(data));

    default:
      return jsonResponse_(
        { error: 'Unknown POST action: ' + action },
        400
      );
  }
}


// ★ 新增：移動桌位（搬「今天、尚未關帳/未 CLOSED」的所有訂單）
function moveTable_(payload) {
  const source = String(payload.sourceTableName || '').trim();
  const target = String(payload.targetTableName || '').trim();
  if (!source || !target) return { ok:false, error:'sourceTableName / targetTableName is required' };
  if (source === target) return { ok:false, error:'sourceTableName must be different from targetTableName' };

  const ss = SpreadsheetApp.getActive();
  const sheet = ss.getSheetByName('Orders');
  if (!sheet) return { ok:false, error:'找不到 Orders 工作表' };

  const values = sheet.getDataRange().getValues();
  if (values.length <= 1) return { ok:true, updated:0, movedOrderIds:[] };

  const header = values[0].map(String);

  const idxOrderId   = header.indexOf('OrderId');
  const idxCreatedAt = header.indexOf('CreatedAt');
  const idxTableName = header.indexOf('TableName');
  const idxStatus    = header.indexOf('Status');
  const idxClosedFlag= header.indexOf('ClosedFlag');

  if (idxTableName < 0) return { ok:false, error:'Orders 表缺少欄位：TableName' };

  const tz = ss.getSpreadsheetTimeZone();
  const todayStr = Utilities.formatDate(new Date(), tz, 'yyyy-MM-dd');

  let updated = 0;
  const movedOrderIds = [];

  const range = sheet.getRange(2, 1, values.length - 1, header.length);
  const rows = range.getValues();

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i];

    const tableName = idxTableName >= 0 ? String(row[idxTableName] || '').trim() : '';
    if (tableName !== source) continue;

    if (idxCreatedAt >= 0) {
      const createdAtVal = row[idxCreatedAt];
      let rowDateStr = todayStr;

      if (createdAtVal instanceof Date) {
        rowDateStr = Utilities.formatDate(createdAtVal, tz, 'yyyy-MM-dd');
      } else if (createdAtVal !== null && createdAtVal !== '') {
        rowDateStr = String(createdAtVal).substring(0, 10);
      }
      if (rowDateStr !== todayStr) continue;
    }

    const status = idxStatus >= 0 ? String(row[idxStatus] || '') : '';
    const closedFlag = idxClosedFlag >= 0 ? String(row[idxClosedFlag] || '') : '';
    const isClosedByStatus = status.toUpperCase() === 'CLOSED';
    const isClosedByFlag   = closedFlag.toUpperCase() === 'Y';
    if (isClosedByStatus || isClosedByFlag) continue;

    row[idxTableName] = target;
    updated++;

    if (idxOrderId >= 0) {
      movedOrderIds.push(String(row[idxOrderId] || ''));
    }
  }

  if (updated > 0) {
    range.setValues(rows);
  }

  return {
    ok: true,
    sourceTableName: source,
    targetTableName: target,
    updated: updated,
    movedOrderIds: movedOrderIds
  };
}

// ===== 讀取「今天的訂單列表」給 iPad 查詢用 =====
function getTodayOrders_() {
  const ss = SpreadsheetApp.getActive();
  const sheet = ss.getSheetByName('Orders');
  if (!sheet) {
    throw new Error('找不到 Orders 工作表');
  }

  const values = sheet.getDataRange().getValues();
  if (values.length <= 1) {
    return { ok: true, orders: [] };
  }

  const header = values[0];

  function findIndex(names) {
    for (var i = 0; i < names.length; i++) {
      var idx = header.indexOf(names[i]);
      if (idx >= 0) return idx;
    }
    return -1;
  }

  var idxDate      = findIndex(['Date', '日期']);
  var idxCreatedAt = findIndex(['CreatedAt', '建立時間', '時間']);
  var idxOrderId   = findIndex(['OrderId', '訂單編號', 'Id']);
  var idxTableName = findIndex(['TableName', '桌位', '桌號']);
  var idxPayMethod = findIndex(['PayMethod', '支付方式', 'Payment']);
  var idxAmount    = findIndex(['Amount', '金額', 'Total', 'TotalAmount']);
  var idxNote      = findIndex(['Note', '備註']);
  var idxStatus    = findIndex(['Status', '狀態']);
  var idxItemsJSON = findIndex(['ItemsJSON', 'ItemsJson', 'itemsjson']);
  var idxCreatedAtOnly = idxCreatedAt;

  if (idxAmount < 0) {
    return { ok: true, orders: [] };
  }

  var tz = ss.getSpreadsheetTimeZone();
  var todayStr = Utilities.formatDate(new Date(), tz, 'yyyy-MM-dd');

  var orders = [];

  for (var i = 1; i < values.length; i++) {
    var row = values[i];

    var dateVal = null;
    if (idxDate >= 0) {
      dateVal = row[idxDate];
    } else if (idxCreatedAt >= 0) {
      dateVal = row[idxCreatedAt];
    }

    var rowDateStr = todayStr;
    if (dateVal instanceof Date) {
      rowDateStr = Utilities.formatDate(dateVal, tz, 'yyyy-MM-dd');
    } else if (dateVal !== null && dateVal !== '') {
      rowDateStr = String(dateVal).substring(0, 10);
    }

    if (rowDateStr !== todayStr) continue;

    var amountVal = row[idxAmount];
    if (typeof amountVal !== 'number') {
      continue;
    }

    var createdAtStr = '';
    if (idxCreatedAtOnly >= 0) {
      createdAtStr = String(row[idxCreatedAtOnly] || '');
    } else if (idxDate >= 0) {
      createdAtStr = String(row[idxDate] || '');
    }

    var items = [];
    var itemsJSONStr = (idxItemsJSON >= 0) ? String(row[idxItemsJSON] || '') : '';

    if (itemsJSONStr) {
      try {
        var parsed = JSON.parse(itemsJSONStr);

        if (Array.isArray(parsed)) {
          items = parsed.map(function (it) {
            return {
              name: String(it.name || it.itemName || ''),
              price: Number(it.price) || 0,
              qty: Number(it.qty || it.quantity) || 0
            };
          });
        } else if (parsed && Array.isArray(parsed.items)) {
          items = parsed.items.map(function (it) {
            return {
              name: String(it.name || it.itemName || ''),
              price: Number(it.price) || 0,
              qty: Number(it.qty || it.quantity) || 0
            };
          });
        }
      } catch (e) {
        // 解析失敗就保持空陣列
      }
    }

    var orderObj = {
      orderId:   idxOrderId   >= 0 ? String(row[idxOrderId] || '')   : '',
      tableName: idxTableName >= 0 ? String(row[idxTableName] || '') : '',
      payMethod: idxPayMethod >= 0 ? String(row[idxPayMethod] || '') : '',
      amount:    amountVal,
      note:      idxNote      >= 0 ? String(row[idxNote] || '')      : '',
      status:    idxStatus    >= 0 ? String(row[idxStatus] || '')    : '',
      createdAt: createdAtStr,
      items:     items,
      itemsJSON: itemsJSONStr
    };

    orders.push(orderObj);
  }

  return {
    ok: true,
    orders: orders
  };
}

/*******************************************************
 * getMenu_：給 iPad 前台用的菜單（分類 + 品項 + 類別加購）
 *******************************************************/

function getMenu_() {
  var ss = getPOSSpreadsheet_();
  var catSheet = ss.getSheetByName('Categories');
  var itemSheet = ss.getSheetByName('Items');
  var addOnSheet = ss.getSheetByName('CategoryAddOns');

  var cats = [];
  var items = [];
  var categoryAddOns = [];

  // ----- Categories -----
  if (catSheet) {
    var catValues = catSheet.getDataRange().getValues();
    if (catValues.length > 1) {
      var header = catValues[0];
      var isNew = String(header[0]).trim() === 'CategoryId';

      for (var i = 1; i < catValues.length; i++) {
        var row = catValues[i];
        var catId, name, sortOrder, isActive;

        if (isNew) {
          catId = row[0];
          name = row[1];
          sortOrder = row[2];
          isActive = row[3];
        } else {
          name = row[0];
          sortOrder = row[1];
          isActive = row[2];
          catId = name;
        }

        if (!name) continue;
        if (String(isActive).toUpperCase() === 'FALSE') continue;

        cats.push({
          categoryId: catId || name,
          name: name,
          sortOrder: sortOrder || 0
        });
      }
    }
  }

  // fallback：完全讀不到分類 → 直接丟 11 個預設分類，並寫回 Categories Sheet
  if (cats.length === 0) {
    var defaultCats = [
      { categoryId: 'CAT001', name: '義式咖啡', sortOrder: 1 },
      { categoryId: 'CAT002', name: '手沖咖啡', sortOrder: 2 },
      { categoryId: 'CAT003', name: 'SOE',     sortOrder: 3 },
      { categoryId: 'CAT004', name: '茶類',     sortOrder: 4 },
      { categoryId: 'CAT005', name: '牛奶類',   sortOrder: 5 },
      { categoryId: 'CAT006', name: '冰滴',     sortOrder: 6 },
      { categoryId: 'CAT007', name: '甜點鹹食', sortOrder: 7 },
      { categoryId: 'CAT008', name: '酒類',     sortOrder: 8 },
      { categoryId: 'CAT009', name: '咖啡豆',   sortOrder: 9 },
      { categoryId: 'CAT010', name: '配件',     sortOrder: 10 },
      { categoryId: 'CAT011', name: '整模蛋糕', sortOrder: 11 }
    ];

    cats = defaultCats;

    if (catSheet) {
      var lastRow = catSheet.getLastRow();
      if (lastRow <= 1) {
        var rows = defaultCats.map(function(c) {
          return [c.categoryId, c.name, c.sortOrder, true];
        });
        catSheet.getRange(2, 1, rows.length, rows[0].length).setValues(rows);
      }
    }
  }

  // ----- Items -----
  if (itemSheet) {
    var itemValues = itemSheet.getDataRange().getValues();
    if (itemValues.length > 1) {
      var iHeader = itemValues[0];
      var isNewItem = String(iHeader[0]).trim() === 'ItemId';

      for (var j = 1; j < itemValues.length; j++) {
        var r = itemValues[j];

        var itemId, categoryId, name2, price, isActive2, allowOat, optionsJSON, addOnsJSON;

        if (isNewItem) {
          itemId      = r[0];
          categoryId  = r[1];
          name2       = r[2];
          price       = r[3];
          isActive2   = r[4];
          allowOat    = r[5];
          optionsJSON = r[6];
          addOnsJSON  = r[7];
        } else {
          categoryId  = r[0];
          name2       = r[1];
          price       = r[2];
          isActive2   = r[3];
          allowOat    = r[4];
          optionsJSON = r[5] || '';
          addOnsJSON  = r[6] || '';
          itemId      = name2;
        }

        if (!name2 || !categoryId) continue;
        if (String(isActive2).toUpperCase() === 'FALSE') continue;

        var options = [];
        var addOnsInline = [];

        if (typeof optionsJSON === 'string') {
          try { options = JSON.parse(optionsJSON); } catch (e) {}
        }
        if (typeof addOnsJSON === 'string') {
          try { addOnsInline = JSON.parse(addOnsJSON); } catch (e2) {}
        }

        items.push({
          itemId: itemId,
          categoryId: categoryId,
          name: name2,
          price: Number(price) || 0,
          allowOat: !!allowOat,
          options: options,
          addOns: addOnsInline
        });
      }
    }
  }

  // ----- CategoryAddOns -----
  if (addOnSheet) {
    var aoValues = addOnSheet.getDataRange().getValues();
    if (aoValues.length > 1) {
      for (var k = 1; k < aoValues.length; k++) {
        var a = aoValues[k];
        var addOnId   = a[0];
        var cId       = a[1];
        var addOnName = a[2];
        var addOnPrice= a[3];
        var aoActive  = a[4];

        if (!cId || !addOnName) continue;
        if (String(aoActive).toUpperCase() === 'FALSE') continue;

        categoryAddOns.push({
          addOnId: addOnId || addOnName,
          categoryId: cId,
          name: addOnName,
          price: Number(addOnPrice) || 0
        });
      }
    }
  }

  return {
    categories: cats,
    items: items,
    categoryAddOns: categoryAddOns
  };
}

/*******************************************************
 * 後台管理：getAdminMenu_ / saveAdminMenu_
 *******************************************************/

function getAdminMenu_() {
  var ss = getPOSSpreadsheet_();
  var catSheet = ss.getSheetByName('Categories');
  var itemSheet = ss.getSheetByName('Items');

  if (!catSheet || !itemSheet) {
    return { error: 'Categories or Items sheet not found' };
  }

  var catValues = catSheet.getDataRange().getValues();
  var itemValues = itemSheet.getDataRange().getValues();
  if (catValues.length < 2) {
    return { categories: [] };
  }

  var headerCat = catValues[0];
  var isNewCat = String(headerCat[0]).trim() === 'CategoryId';
  var cats = [];

  for (var i = 1; i < catValues.length; i++) {
    var row = catValues[i];
    var catId, name, sortOrder, isActive;

    if (isNewCat) {
      catId = row[0];
      name = row[1];
      sortOrder = row[2];
      isActive = row[3];
    } else {
      name = row[0];
      sortOrder = row[1];
      isActive = row[2];
      catId = name;
    }
    if (!name) continue;

    if (String(isActive).toUpperCase() === 'FALSE') continue;

    cats.push({
      categoryId: catId || name,
      name: name,
      sortOrder: sortOrder || 0,
      items: []
    });
  }

  if (itemValues.length > 1) {
    var headerItem = itemValues[0];
    var isNewItem = String(headerItem[0]).trim() === 'ItemId';

    var idxItemId, idxCategoryId, idxName, idxPrice, idxIsActive, idxAllowOat, idxOptionsJSON, idxAddOnsJSON;

    if (isNewItem) {
      idxItemId      = 0;
      idxCategoryId  = 1;
      idxName        = 2;
      idxPrice       = 3;
      idxIsActive    = 4;
      idxAllowOat    = 5;
      idxOptionsJSON = 6;
      idxAddOnsJSON  = 7;
    } else {
      idxCategoryId  = 0;
      idxName        = 1;
      idxPrice       = 2;
      idxIsActive    = 3;
      idxAllowOat    = 4;
      idxOptionsJSON = 5;
      idxAddOnsJSON  = 6;
      idxItemId      = null;
    }

    var itemsByCat = {};

    for (var j = 1; j < itemValues.length; j++) {
      var r = itemValues[j];
      var itemId = idxItemId !== null ? r[idxItemId] : null;
      var categoryId = r[idxCategoryId];
      var name2 = r[idxName];
      var price = r[idxPrice];
      var isActive2 = r[idxIsActive];
      var allowOatCell = r[idxAllowOat];
      var addOnsJSON = r[idxAddOnsJSON];

      if (!name2 || !categoryId) continue;

      var enabled = String(isActive2).toUpperCase() !== 'FALSE';

      var addOns = [];
      if (typeof addOnsJSON === 'string' && addOnsJSON.trim() !== '') {
        try {
          var raw = JSON.parse(addOnsJSON);
          if (Array.isArray(raw)) {
            raw.forEach(function(a) {
              if (!a) return;
              var addOnName = a.name || '';
              if (!addOnName) return;
              var addOnId = a.addOnId || a.id || addOnName;
              var priceA = Number(a.price) || 0;
              var enabledA;

              if (typeof a.enabled !== 'undefined') {
                enabledA = !!a.enabled;
              } else if (typeof a.isActive !== 'undefined') {
                enabledA = String(a.isActive).toUpperCase() !== 'FALSE';
              } else {
                enabledA = true;
              }

              addOns.push({
                addOnId: addOnId,
                name: addOnName,
                price: priceA,
                enabled: enabledA
              });
            });
          }
        } catch (e) {}
      }

      var itemObj = {
        itemId: itemId || name2,
        categoryId: categoryId,
        name: name2,
        price: Number(price) || 0,
        enabled: enabled,
        allowOat: String(allowOatCell).toUpperCase() === 'TRUE',
        addOns: addOns
      };

      if (!itemsByCat[categoryId]) itemsByCat[categoryId] = [];
      itemsByCat[categoryId].push(itemObj);
    }

    cats.forEach(function(c) {
      c.items = itemsByCat[c.categoryId] || [];
    });
  }

  return { categories: cats };
}

function saveAdminMenu_(data) {
  var ss = getPOSSpreadsheet_();
  var itemSheet = ss.getSheetByName('Items');
  if (!itemSheet) {
    return { ok: false, error: 'Items sheet not found' };
  }

  var categories = data.categories || [];
  var flatItems = [];
  categories.forEach(function (c) {
    (c.items || []).forEach(function (it) {
      flatItems.push({
        categoryId: c.categoryId,
        item: it
      });
    });
  });

  if (flatItems.length === 0) {
    return { ok: false, error: 'No items to write (categories is empty)' };
  }

  var range = itemSheet.getDataRange();
  var values = range.getValues();
  if (values.length < 1) {
    return { ok: false, error: 'Items sheet has no header' };
  }

  var header = values[0];
  var isNewItem = String(header[0]).trim() === 'ItemId';

  var idxItemId, idxCategoryId, idxName, idxPrice,
      idxIsActive, idxAllowOat, idxOptionsJSON, idxAddOnsJSON;

  if (isNewItem) {
    idxItemId      = 0;
    idxCategoryId  = 1;
    idxName        = 2;
    idxPrice       = 3;
    idxIsActive    = 4;
    idxAllowOat    = 5;
    idxOptionsJSON = 6;
    idxAddOnsJSON  = 7;
  } else {
    idxCategoryId  = 0;
    idxName        = 1;
    idxPrice       = 2;
    idxIsActive    = 3;
    idxAllowOat    = 4;
    idxOptionsJSON = 5;
    idxAddOnsJSON  = 6;
    idxItemId      = null;
  }

  var optionsById = {};
  var optionsByName = {};
  if (values.length > 1) {
    for (var r = 1; r < values.length; r++) {
      var row = values[r];
      var oldId   = (idxItemId !== null) ? row[idxItemId] : null;
      var oldName = row[idxName];
      var optJSON = row[idxOptionsJSON];

      if (oldId) {
        optionsById[String(oldId)] = optJSON;
      }
      if (oldName) {
        optionsByName[String(oldName)] = optJSON;
      }
    }
  }

  var newRows = [];
  var updatedCount = 0;
  var newCount = 0;

  flatItems.forEach(function (rowInfo) {
    var cId = rowInfo.categoryId || '';
    var it  = rowInfo.item || {};

    var name  = it.name || '';
    if (!name) return;

    var price   = Number(it.price) || 0;
    var enabled = (typeof it.enabled === 'undefined') ? true : !!it.enabled;
    var allowOat = !!it.allowOat;
    var addOnsJSON = JSON.stringify(it.addOns || []);

    var itemId = it.itemId;
    var optionsJSON = '';

    if (isNewItem) {
      if (itemId && optionsById.hasOwnProperty(String(itemId))) {
        optionsJSON = optionsById[String(itemId)];
      } else if (optionsByName.hasOwnProperty(name)) {
        optionsJSON = optionsByName[name];
      }

      if (!itemId) {
        itemId = 'ITM-' + Utilities.getUuid();
        newCount++;
      } else {
        updatedCount++;
      }

      newRows.push([
        itemId,
        cId,
        name,
        price,
        enabled,
        allowOat,
        optionsJSON,
        addOnsJSON
      ]);
    } else {
      if (optionsByName.hasOwnProperty(name)) {
        optionsJSON = optionsByName[name];
        updatedCount++;
      } else {
        newCount++;
      }

      newRows.push([
        cId,
        name,
        price,
        enabled,
        allowOat,
        optionsJSON,
        addOnsJSON
      ]);
    }
  });

  var lastRow = itemSheet.getLastRow();
  if (lastRow > 1) {
    itemSheet
      .getRange(2, 1, lastRow - 1, itemSheet.getLastColumn())
      .clearContent();
  }

  if (newRows.length > 0) {
    itemSheet
      .getRange(2, 1, newRows.length, newRows[0].length)
      .setValues(newRows);
  }

  return {
    ok: true,
    updatedCount: updatedCount,
    newCount: newCount
  };
}

/*******************************************************
 * Orders：建立訂單 / 更新狀態 / 關帳 / 今日訂單 / 刪除訂單
 *******************************************************/

function createOrderFromDevice_(payload) {
  var order = payload.order || payload;

  var newOrder = JSON.parse(JSON.stringify(order || {}));

  var status = String(newOrder.status || '').trim().toUpperCase();
  var hasClientOrderId = !!String(newOrder.orderId || '').trim();

  if (status === 'PENDING' && hasClientOrderId) {
    return createOrder_(newOrder);
  }

  newOrder.orderId = Utilities.getUuid();
  return createOrder_(newOrder);
}

function createOrder_(payload) {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Orders');
  if (!sheet) {
    throw new Error('Orders sheet not found, please run initPOSDatabase');
  }

  var order = payload.order || payload;
  var orderId = order.orderId || Utilities.getUuid();
  var now = new Date();
  var tz = Session.getScriptTimeZone();
  var createdAtStr = Utilities.formatDate(now, tz, 'yyyy-MM-dd HH:mm:ss');

  var itemsJSON = JSON.stringify(order.items || []);
  var amount = Number(order.amount) || 0;
  var tableName = order.tableName || '';
  var payMethod = order.payMethod || '';

  var rawStatus = String(order.status || '').trim();
  var status = rawStatus;
  if (!status) {
    status = payMethod ? 'PAID' : 'PENDING';
  }

  var note = order.note || '';
  var linePayTxnId = order.linePayTransactionId || '';

  sheet.appendRow([
    orderId,
    createdAtStr,
    tableName,
    itemsJSON,
    amount,
    payMethod,
    status,
    note,
    linePayTxnId,
    ''
  ]);

  return {
    ok: true,
    orderId: orderId,
    createdAt: createdAtStr
  };
}

function updateOrderStatus_(payload) {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Orders');
  if (!sheet) {
    throw new Error('Orders sheet not found');
  }

  var orderId = String(payload.orderId || '').trim();
  if (!orderId) {
    return { ok: false, error: 'orderId is required' };
  }

  var newStatus = String(payload.status || '').trim().toUpperCase();
  var payMethod = String(payload.payMethod || '').trim();
  var linePayTxnId = String(payload.linePayTransactionId || '').trim();

  if (newStatus === 'PAID' && !payMethod) {
    return { ok: false, error: 'payMethod is required when status=PAID' };
  }

  var data = sheet.getDataRange().getValues();
  var updated = false;

  for (var i = 1; i < data.length; i++) {
    if (String(data[i][0] || '').trim() === orderId) {
      if (payMethod) {
        sheet.getRange(i + 1, 6).setValue(payMethod);
      }

      if (newStatus) {
        sheet.getRange(i + 1, 7).setValue(newStatus);
      }

      if (linePayTxnId) {
        sheet.getRange(i + 1, 9).setValue(linePayTxnId);
      }

      updated = true;
      break;
    }
  }

  if (!updated) {
    return { ok: false, error: 'Order not found: ' + orderId };
  }

  return {
    ok: true,
    orderId: orderId,
    status: newStatus,
    payMethod: payMethod
  };
}

function updateOrderPaymentStatus_(payload) {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Orders');
  if (!sheet) throw new Error('Orders sheet not found');

  var orderId = String(payload.orderId || '').trim();
  var status = String(payload.status || '').trim().toUpperCase();
  var payMethod = String(payload.payMethod || '').trim();
  var linePayTxnId = (payload.linePayTransactionId == null) ? '' : String(payload.linePayTransactionId).trim();

  if (!orderId) return { ok:false, error:'orderId is required' };
  if (status !== 'PAID' && status !== 'PENDING') return { ok:false, error:'status must be PAID or PENDING' };
  if (!payMethod && status === 'PAID') return { ok:false, error:'payMethod is required when status=PAID' };

  var data = sheet.getDataRange().getValues();

  for (var i = 1; i < data.length; i++) {
    if (String(data[i][0]) === orderId) {
      sheet.getRange(i + 1, 6).setValue(payMethod);
      sheet.getRange(i + 1, 7).setValue(status);

      if (linePayTxnId) {
        sheet.getRange(i + 1, 9).setValue(linePayTxnId);
      }
      return { ok:true, orderId: orderId, status: status, payMethod: payMethod, linePayTransactionId: linePayTxnId };
    }
  }

  return { ok:false, error:'Order not found: ' + orderId };
}

function dailyClose_(payload) {
  var ss = getPOSSpreadsheet_();
  var orderSheet = ss.getSheetByName('Orders');
  var closeSheet = ss.getSheetByName('CloseShift');
  if (!orderSheet || !closeSheet) {
    throw new Error('Orders / CloseShift sheet not found');
  }

  var tz = Session.getScriptTimeZone();
  var now = new Date();
  var dateStr = (payload && payload.date) ||
                Utilities.formatDate(now, tz, 'yyyy-MM-dd');

  var values = orderSheet.getDataRange().getValues();
  var totalAmount = 0;
  var totalCash = 0;
  var totalCard = 0;
  var totalLinePay = 0;
  var totalTapPay = 0;
  var count = 0;

  var rowsToClose = [];

  for (var i = 1; i < values.length; i++) {
    var row = values[i];
    var createdAt = row[1];
    var amount = Number(row[4]) || 0;
    var payMethod = row[5];
    var status = row[6];
    var closedFlag = row[9];

    if (!createdAt || !status) continue;
    if (String(closedFlag).toUpperCase() === 'Y') continue;

    var createdDateStr;
    if (createdAt instanceof Date) {
      createdDateStr = Utilities.formatDate(createdAt, tz, 'yyyy-MM-dd');
    } else {
      createdDateStr = String(createdAt).substring(0, 10);
    }

    if (createdDateStr !== dateStr) continue;
    if (String(status).toUpperCase() !== 'PAID') continue;

    totalAmount += amount;
    count++;

    var pm = String(payMethod || '').toUpperCase();
    if (pm === 'CASH') totalCash += amount;
    else if (pm === 'CARD') totalCard += amount;
    else if (pm === 'LINEPAY') totalLinePay += amount;
    else if (pm === 'TAPPAY') totalTapPay += amount;

    rowsToClose.push(i + 1);
  }

  closeSheet.appendRow([
    dateStr,
    totalAmount,
    totalCash,
    totalCard,
    totalLinePay,
    totalTapPay,
    count,
    now
  ]);

  rowsToClose.forEach(function (rowIndex) {
    orderSheet.getRange(rowIndex, 10).setValue('Y');
  });

  return {
    ok: true,
    date: dateStr,
    totalAmount: totalAmount,
    totalCash: totalCash,
    totalCard: totalCard,
    totalLinePay: totalLinePay,
    totalTapPay: totalTapPay,
    orderCount: count,
    closedRows: rowsToClose.length
  };
}

function isPaidOrderRow_(status, payMethod) {
  var s = String(status || '').trim().toUpperCase();
  if (s === 'PAID') return true;
  if (s === 'PENDING') return false;
  return false;
}

function getLiveBusinessSummary_(targetDate) {
  const ss = SpreadsheetApp.getActive();
  const ordersSheet = ss.getSheetByName('Orders');
  if (!ordersSheet) throw new Error('找不到 Orders 工作表');

  const values = ordersSheet.getDataRange().getValues();
  const tz = ss.getSpreadsheetTimeZone();
  const todayStr = targetDate || Utilities.formatDate(new Date(), tz, 'yyyy-MM-dd');

  if (values.length <= 1) {
    return {
      ok: true,
      date: todayStr,
      liveTotalAmount: 0,
      paidTotalAmount: 0,
      pendingTotalAmount: 0,
      totalCash: 0,
      totalCard: 0,
      totalLinePay: 0,
      totalTapPay: 0,
      paidOrderCount: 0,
      pendingOrderCount: 0
    };
  }

  const header = values[0];
  const idxDate       = header.indexOf('Date');
  const idxCreatedAt  = header.indexOf('CreatedAt');
  const idxPayMethod  = header.indexOf('PayMethod');
  const idxAmount     = header.indexOf('Amount');
  const idxStatus     = header.indexOf('Status');
  const idxClosedFlag = header.indexOf('ClosedFlag');

  if (idxAmount < 0) throw new Error('Orders 表缺少欄位：Amount');
  if (idxDate < 0 && idxCreatedAt < 0) throw new Error('Orders 表缺少欄位：Date 或 CreatedAt');

  let liveTotalAmount = 0;
  let paidTotalAmount = 0;
  let pendingTotalAmount = 0;
  let totalCash = 0;
  let totalCard = 0;
  let totalLinePay = 0;
  let totalTapPay = 0;
  let paidOrderCount = 0;
  let pendingOrderCount = 0;

  for (let i = 1; i < values.length; i++) {
    const row = values[i];

    const statusVal   = idxStatus >= 0 ? row[idxStatus] : '';
    const closedFlag  = idxClosedFlag >= 0 ? row[idxClosedFlag] : '';
    const statusUpper = String(statusVal || '').trim().toUpperCase();
    const closedUpper = String(closedFlag || '').trim().toUpperCase();

    if (closedUpper === 'Y') continue;
    if (statusUpper === 'CLOSED' || statusUpper === 'VOID') continue;

    let dateVal = null;
    if (idxDate >= 0) dateVal = row[idxDate];
    else if (idxCreatedAt >= 0) dateVal = row[idxCreatedAt];

    let rowDateStr = todayStr;
    if (dateVal instanceof Date) {
      rowDateStr = Utilities.formatDate(dateVal, tz, 'yyyy-MM-dd');
    } else if (dateVal !== null && dateVal !== '') {
      rowDateStr = String(dateVal).substring(0, 10);
    }
    if (rowDateStr !== todayStr) continue;

    const amount = Number(row[idxAmount]) || 0;
    if (!amount) continue;

    if (statusUpper === 'PAID') {
      paidOrderCount++;
      paidTotalAmount += amount;
      liveTotalAmount += amount;

      const methodUpper = String(idxPayMethod >= 0 ? row[idxPayMethod] || '' : '').trim().toUpperCase();
      switch (methodUpper) {
        case 'CASH':    totalCash += amount;    break;
        case 'CARD':    totalCard += amount;    break;
        case 'LINEPAY': totalLinePay += amount; break;
        case 'TAPPAY':  totalTapPay += amount;  break;
      }
    } else if (statusUpper === 'PENDING') {
      pendingOrderCount++;
      pendingTotalAmount += amount;
      liveTotalAmount += amount;
    }
  }

  return {
    ok: true,
    date: todayStr,
    liveTotalAmount: liveTotalAmount,
    paidTotalAmount: paidTotalAmount,
    pendingTotalAmount: pendingTotalAmount,
    totalCash: totalCash,
    totalCard: totalCard,
    totalLinePay: totalLinePay,
    totalTapPay: totalTapPay,
    paidOrderCount: paidOrderCount,
    pendingOrderCount: pendingOrderCount
  };
}

function getCloseShiftSummary_(targetDate) {
  const ss = SpreadsheetApp.getActive();
  const ordersSheet = ss.getSheetByName('Orders');
  if (!ordersSheet) throw new Error('找不到 Orders 工作表');

  const values = ordersSheet.getDataRange().getValues();
  const tz = ss.getSpreadsheetTimeZone();
  const todayStr = targetDate || Utilities.formatDate(new Date(), tz, 'yyyy-MM-dd');

  if (values.length <= 1) {
    return {
      ok: true,
      date: todayStr,
      closeableTotalAmount: 0,
      totalCash: 0,
      totalCard: 0,
      totalLinePay: 0,
      totalTapPay: 0,
      orderCount: 0
    };
  }

  const header = values[0];
  const idxDate       = header.indexOf('Date');
  const idxCreatedAt  = header.indexOf('CreatedAt');
  const idxPayMethod  = header.indexOf('PayMethod');
  const idxAmount     = header.indexOf('Amount');
  const idxStatus     = header.indexOf('Status');
  const idxClosedFlag = header.indexOf('ClosedFlag');

  if (idxPayMethod < 0 || idxAmount < 0) throw new Error('Orders 表缺少欄位：PayMethod / Amount');
  if (idxDate < 0 && idxCreatedAt < 0) throw new Error('Orders 表缺少欄位：Date 或 CreatedAt');

  let closeableTotalAmount = 0;
  let totalCash = 0;
  let totalCard = 0;
  let totalLinePay = 0;
  let totalTapPay = 0;
  let orderCount = 0;

  for (let i = 1; i < values.length; i++) {
    const row = values[i];

    const statusVal   = idxStatus >= 0 ? row[idxStatus] : '';
    const closedFlag  = idxClosedFlag >= 0 ? row[idxClosedFlag] : '';
    const statusUpper = String(statusVal || '').trim().toUpperCase();
    const closedUpper = String(closedFlag || '').trim().toUpperCase();

    if (statusUpper === 'CLOSED' || closedUpper === 'Y') continue;

    let dateVal = null;
    if (idxDate >= 0) dateVal = row[idxDate];
    else if (idxCreatedAt >= 0) dateVal = row[idxCreatedAt];

    let rowDateStr = todayStr;
    if (dateVal instanceof Date) {
      rowDateStr = Utilities.formatDate(dateVal, tz, 'yyyy-MM-dd');
    } else if (dateVal !== null && dateVal !== '') {
      rowDateStr = String(dateVal).substring(0, 10);
    }
    if (rowDateStr !== todayStr) continue;

    const amount = Number(row[idxAmount]) || 0;
    if (!amount) continue;
    if (statusUpper !== 'PAID') continue;

    orderCount++;
    closeableTotalAmount += amount;

    const methodUpper = String(row[idxPayMethod] || '').trim().toUpperCase();
    switch (methodUpper) {
      case 'CASH':    totalCash += amount;    break;
      case 'CARD':    totalCard += amount;    break;
      case 'LINEPAY': totalLinePay += amount; break;
      case 'TAPPAY':  totalTapPay += amount;  break;
    }
  }

  return {
    ok: true,
    date: todayStr,
    closeableTotalAmount: closeableTotalAmount,
    totalCash: totalCash,
    totalCard: totalCard,
    totalLinePay: totalLinePay,
    totalTapPay: totalTapPay,
    orderCount: orderCount
  };
}

function getArchiveSheetName_(dateStr) {
  var monthKey = String(dateStr || '').substring(0, 7).replace('-', '_');
  return 'Orders_Archive_' + monthKey;
}

function getPreviousMonthRange_(baseDate, tz) {
  var year = Number(Utilities.formatDate(baseDate, tz, 'yyyy'));
  var month = Number(Utilities.formatDate(baseDate, tz, 'M'));

  var prevYear = year;
  var prevMonth = month - 1;

  if (prevMonth <= 0) {
    prevMonth = 12;
    prevYear = year - 1;
  }

  var start = new Date(prevYear, prevMonth - 1, 1);
  var end = new Date(year, month - 1, 1);

  var startStr = Utilities.formatDate(start, tz, 'yyyy-MM-dd');
  var endStr = Utilities.formatDate(end, tz, 'yyyy-MM-dd');
  var archiveMonthDateStr = Utilities.formatDate(start, tz, 'yyyy-MM-dd');

  return {
    start: start,
    end: end,
    startStr: startStr,
    endStr: endStr,
    archiveMonthDateStr: archiveMonthDateStr
  };
}

function ensureArchiveSheet_(archiveSheetName, ordersHeader) {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName(archiveSheetName);

  if (!sheet) {
    sheet = ss.insertSheet(archiveSheetName);
  }

  if (sheet.getLastRow() === 0) {
    var archiveHeader = ordersHeader.slice();
    archiveHeader.push('ArchivedAt');
    archiveHeader.push('ArchiveSource');
    sheet.getRange(1, 1, 1, archiveHeader.length).setValues([archiveHeader]);
    sheet.setFrozenRows(1);
  }

  return sheet;
}

function getRowDateStrForArchive_(dateVal, fallbackDateStr, tz) {
  if (dateVal instanceof Date) {
    return Utilities.formatDate(dateVal, tz, 'yyyy-MM-dd');
  }
  if (dateVal !== null && dateVal !== '') {
    return String(dateVal).substring(0, 10);
  }
  return fallbackDateStr;
}

function archiveAndDeleteClosedPaidOrders_(archiveMonthDateStr, rowsToArchive) {
  var ss = getPOSSpreadsheet_();
  var ordersSheet = ss.getSheetByName('Orders');
  if (!ordersSheet) throw new Error('Orders sheet not found');

  if (!rowsToArchive || rowsToArchive.length === 0) {
    return {
      ok: true,
      archiveSheetName: getArchiveSheetName_(archiveMonthDateStr),
      archivedRows: 0,
      deletedRows: 0
    };
  }

  var lastCol = ordersSheet.getLastColumn();
  var allValues = ordersSheet.getDataRange().getValues();
  var header = allValues[0];

  var archiveSheetName = getArchiveSheetName_(archiveMonthDateStr);
  var archiveSheet = ensureArchiveSheet_(archiveSheetName, header);

  // 建立要封存的列號 Set（1-based，含表頭，所以 rowsToArchive 的值就是實際列號）
  var archiveSet = {};
  rowsToArchive.forEach(function(r) { archiveSet[r] = true; });

  var now = new Date();
  var archiveRows = [];
  var keepRows = [];   // 不包含表頭

  for (var i = 1; i < allValues.length; i++) {
    var sheetRowNum = i + 1; // 1-based，+1 是因為表頭在第1列
    if (archiveSet[sheetRowNum]) {
      var archiveRow = allValues[i].slice();
      archiveRow.push(now);
      archiveRow.push('monthlyCloseShiftArchive');
      archiveRows.push(archiveRow);
    } else {
      keepRows.push(allValues[i]);
    }
  }

  // 1) 寫入封存 sheet
  if (archiveRows.length > 0) {
    archiveSheet
      .getRange(archiveSheet.getLastRow() + 1, 1, archiveRows.length, archiveRows[0].length)
      .setValues(archiveRows);
  }

  // 2) 用「清空 + 寫回剩餘列」取代逐列 deleteRow（快很多）
  var dataLastRow = ordersSheet.getLastRow();
  if (dataLastRow > 1) {
    ordersSheet.getRange(2, 1, dataLastRow - 1, lastCol).clearContent();
  }
  if (keepRows.length > 0) {
    ordersSheet.getRange(2, 1, keepRows.length, lastCol).setValues(keepRows);
  }

  return {
    ok: true,
    archiveSheetName: archiveSheetName,
    archivedRows: archiveRows.length,
    deletedRows: archiveRows.length
  };
}

function archivePreviousMonthClosedOrders_(baseDate, tz) {
  var ss = SpreadsheetApp.getActive();
  var ordersSheet = ss.getSheetByName('Orders');
  if (!ordersSheet) throw new Error('Orders sheet not found');

  var values = ordersSheet.getDataRange().getValues();
  var rangeInfo = getPreviousMonthRange_(baseDate, tz);

  if (values.length <= 1) {
    return {
      ok: true,
      archiveSheetName: getArchiveSheetName_(rangeInfo.archiveMonthDateStr),
      archivedRows: 0,
      deletedRows: 0,
      archiveMonthStart: rangeInfo.startStr,
      archiveMonthEndExclusive: rangeInfo.endStr
    };
  }

  var header = values[0];
  var idxDate       = header.indexOf('Date');
  var idxCreatedAt  = header.indexOf('CreatedAt');
  var idxStatus     = header.indexOf('Status');
  var idxClosedFlag = header.indexOf('ClosedFlag');

  if (idxCreatedAt < 0 && idxDate < 0) {
    throw new Error('Orders 表缺少 Date 或 CreatedAt 欄位');
  }
  if (idxClosedFlag < 0) {
    throw new Error('Orders 缺少 ClosedFlag 欄位');
  }

  var rowsToArchive = [];

  for (var i = 1; i < values.length; i++) {
    var row = values[i];
    var closedUpper = String(idxClosedFlag >= 0 ? row[idxClosedFlag] || '' : '').trim().toUpperCase();
    if (closedUpper !== 'Y') continue;

    var statusUpper = String(idxStatus >= 0 ? row[idxStatus] || '' : '').trim().toUpperCase();
    if (statusUpper && statusUpper !== 'PAID' && statusUpper !== 'CLOSED') continue;

    var dateVal = null;
    if (idxDate >= 0) dateVal = row[idxDate];
    else if (idxCreatedAt >= 0) dateVal = row[idxCreatedAt];

    var rowDateStr = getRowDateStrForArchive_(dateVal, rangeInfo.startStr, tz);
    if (rowDateStr < rangeInfo.startStr) continue;
    if (rowDateStr >= rangeInfo.endStr) continue;

    rowsToArchive.push(i + 1);
  }

  var archiveResult = archiveAndDeleteClosedPaidOrders_(rangeInfo.archiveMonthDateStr, rowsToArchive);
  archiveResult.archiveMonthStart = rangeInfo.startStr;
  archiveResult.archiveMonthEndExclusive = rangeInfo.endStr;
  return archiveResult;
}

function closeShift_(payload) {
  const ss = SpreadsheetApp.getActive();
  const tz = ss.getSpreadsheetTimeZone();

  const targetDate = (payload && payload.date)
    ? payload.date
    : Utilities.formatDate(new Date(), tz, 'yyyy-MM-dd');

  const baseDate = new Date(targetDate + 'T00:00:00');
  const summary = getCloseShiftSummary_(targetDate);

  let closedRows = 0;
  let wroteCloseShiftRow = false;

  if (summary.orderCount > 0) {
    const closeSheetName = 'CloseShift';
    const closeSheet = ss.getSheetByName(closeSheetName) || ss.insertSheet(closeSheetName);

    if (closeSheet.getLastRow() === 0) {
      closeSheet.appendRow([
        'Date', 'TotalAmount', 'Cash', 'Card', 'LinePay', 'TapPay', 'OrderCount', 'CreatedAt'
      ]);
    }

    closeSheet.appendRow([
      summary.date,
      summary.closeableTotalAmount,
      summary.totalCash,
      summary.totalCard,
      summary.totalLinePay,
      summary.totalTapPay,
      summary.orderCount,
      new Date()
    ]);
    wroteCloseShiftRow = true;

    const ordersSheet = ss.getSheetByName('Orders');
    if (!ordersSheet) throw new Error('Orders sheet not found');

    const values = ordersSheet.getDataRange().getValues();
    if (values.length > 1) {
      const header = values[0];
      const idxDate       = header.indexOf('Date');
      const idxCreatedAt  = header.indexOf('CreatedAt');
      const idxStatus     = header.indexOf('Status');
      const idxClosedFlag = header.indexOf('ClosedFlag');

      if (idxClosedFlag < 0) {
        throw new Error('Orders 缺少 ClosedFlag 欄位');
      }

      const dataRange = ordersSheet.getRange(2, 1, values.length - 1, header.length);
      const rows = dataRange.getValues();

      for (let i = 0; i < rows.length; i++) {
        const row = rows[i];

        const closedFlagVal = idxClosedFlag >= 0 ? row[idxClosedFlag] : '';
        const closedUpper = String(closedFlagVal || '').trim().toUpperCase();
        if (closedUpper === 'Y') continue;

        let dateVal = null;
        if (idxDate >= 0) dateVal = row[idxDate];
        else if (idxCreatedAt >= 0) dateVal = row[idxCreatedAt];

        let rowDateStr = targetDate;
        if (dateVal instanceof Date) {
          rowDateStr = Utilities.formatDate(dateVal, tz, 'yyyy-MM-dd');
        } else if (dateVal !== null && dateVal !== '') {
          rowDateStr = String(dateVal).substring(0, 10);
        }
        if (rowDateStr !== targetDate) continue;

        const statusVal = idxStatus >= 0 ? row[idxStatus] : '';
        const statusUpper = String(statusVal || '').trim().toUpperCase();
        if (statusUpper !== 'PAID') continue;

        row[idxClosedFlag] = 'Y';
        closedRows++;
      }

      dataRange.setValues(rows);
    }
  }

  let archiveResult = archivePreviousMonthClosedOrders_(baseDate, tz);

  let message = '';
  if (summary.orderCount > 0) {
    message = '關帳完成';
  } else {
    message = '沒有尚未關帳的已付款訂單';
  }

  if (archiveResult.archivedRows > 0) {
    message += '；已封存上月已關帳資料';
  }

  return Object.assign({}, summary, {
    closedRows: closedRows,
    archivedRows: archiveResult.archivedRows || 0,
    deletedRows: archiveResult.deletedRows || 0,
    archiveSheetName: archiveResult.archiveSheetName || null,
    archiveMonthStart: archiveResult.archiveMonthStart || null,
    archiveMonthEndExclusive: archiveResult.archiveMonthEndExclusive || null,
    wroteCloseShiftRow: wroteCloseShiftRow,
    message: message
  });
}

function deleteOrder_(data) {
  var orderId = String(data.orderId || '').trim();
  if (!orderId) return { ok: false, error: 'orderId required' };

  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Orders');
  if (!sheet) return { ok: false, error: 'Orders sheet not found' };

  var values = sheet.getDataRange().getValues();
  var foundRow = -1;

  for (var i = 1; i < values.length; i++) {
    var cellId = String(values[i][0] || '').trim();
    if (cellId === orderId) {
      foundRow = i + 1;
      break;
    }
  }

  if (foundRow < 0) return { ok: false, error: 'order not found' };

  sheet.deleteRow(foundRow);
  return { ok: true, orderId: orderId };
}

function updateOrder_(data) {
  var orderId = data.orderId;
  if (!orderId) return { ok: false, error: 'orderId required' };

  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Orders');
  if (!sheet) return { ok: false, error: 'Orders sheet not found' };

  var values = sheet.getDataRange().getValues();
  var targetRow = null;

  for (var i = 1; i < values.length; i++) {
    if (values[i][0] === orderId) {
      targetRow = i + 1;
      break;
    }
  }

  if (!targetRow) return { ok: false, error: 'order not found' };

  sheet.getRange(targetRow, 4).setValue(JSON.stringify(data.items || []));
  sheet.getRange(targetRow, 5).setValue(Number(data.amount) || 0);
  sheet.getRange(targetRow, 8).setValue(data.note || "");

  return { ok: true, orderId: orderId };
}

/*******************************************************
 * debug：看 raw 資料（必要時再用）
 *******************************************************/

function debugMenuRaw_() {
  var ss = getPOSSpreadsheet_();
  var catSheet = ss.getSheetByName('Categories');
  var itemSheet = ss.getSheetByName('Items');

  var catValues = catSheet ? catSheet.getDataRange().getValues() : null;
  var itemValues = itemSheet ? itemSheet.getDataRange().getValues() : null;

  return {
    spreadsheetName: ss.getName(),
    categoriesRaw: catValues,
    itemsRawFirst10: itemValues ? itemValues.slice(0, 10) : null
  };
}

/*******************************************************
 * LINEPAY.gs
 *******************************************************/

var LINEPAY_OFFLINE_CONFIG = {
  channelId: '1657619438',
  channelSecret: '20f91ca064fe145af7f2542b9bc5d15b',
  isSandbox: false,
  merchantDeviceType: 'iPadPOS',
  merchantDeviceProfileId: ''
};

function getLinePayOfflineBaseUrl_() {
  return LINEPAY_OFFLINE_CONFIG.isSandbox
    ? 'https://sandbox-api-pay.line.me'
    : 'https://api-pay.line.me';
}

function callLinePayOfflineApi_(method, path, bodyObj) {
  var baseUrl = getLinePayOfflineBaseUrl_();
  var url = baseUrl + path;

  var payload = bodyObj ? JSON.stringify(bodyObj) : '';
  var headers = {
    'X-LINE-ChannelId': LINEPAY_OFFLINE_CONFIG.channelId,
    'X-LINE-ChannelSecret': LINEPAY_OFFLINE_CONFIG.channelSecret
  };

  if (LINEPAY_OFFLINE_CONFIG.merchantDeviceType) {
    headers['X-LINE-MerchantDeviceType'] = LINEPAY_OFFLINE_CONFIG.merchantDeviceType;
  }
  if (LINEPAY_OFFLINE_CONFIG.merchantDeviceProfileId) {
    headers['X-LINE-MerchantDeviceProfileId'] = LINEPAY_OFFLINE_CONFIG.merchantDeviceProfileId;
  }

  var options = {
    method: method,
    contentType: 'application/json; charset=UTF-8',
    headers: headers,
    payload: payload,
    muteHttpExceptions: true
  };

  var resp = UrlFetchApp.fetch(url, options);
  var code = resp.getResponseCode();
  var text = resp.getContentText() || '';

  var json;
  try {
    json = JSON.parse(text);
  } catch (e) {
    json = { raw: text, parseError: String(e) };
  }

  return {
    httpStatus: code,
    body: json
  };
}

function linePayOfflinePay_(payload) {
  var order = payload.order || payload;
  var oneTimeKey = payload.oneTimeKey;

  if (!order) {
    return { ok: false, error: 'order is required' };
  }
  if (!oneTimeKey) {
    return { ok: false, error: 'oneTimeKey is required' };
  }

  var amount = Number(order.amount) || 0;
  if (!amount) {
    return { ok: false, error: 'order.amount is required and > 0' };
  }

  var orderId = order.orderId || Utilities.getUuid();
  var productName = '眷鳥咖啡訂單';
  if (order.tableName) {
    productName += '（' + order.tableName + '）';
  }

  var body = {
    amount: amount,
    currency: 'TWD',
    orderId: orderId,
    productName: productName,
    oneTimeKey: oneTimeKey,
    capture: true
  };

  var path = '/v2/payments/oneTimeKeys/pay';
  var result = callLinePayOfflineApi_('post', path, body);
  var resp = result.body || {};

  var httpStatus = result.httpStatus;
  var returnCode = resp.returnCode;
  var returnMessage = resp.returnMessage;
  var info = resp.info || null;

  var lpOk = (httpStatus === 200 && String(returnCode) === '0000');

  var orderResult = null;
  if (lpOk) {
    var txnId = info && info.transactionId ? info.transactionId : '';
    var extendedOrder = JSON.parse(JSON.stringify(order));

    extendedOrder.orderId = orderId;
    extendedOrder.payMethod = extendedOrder.payMethod || 'LINEPAY';
    extendedOrder.status = 'PAID';
    extendedOrder.linePayTransactionId = txnId;

    orderResult = createOrder_(extendedOrder);
  }

  return {
    ok: lpOk && (!orderResult || orderResult.ok),
    httpStatus: httpStatus,
    returnCode: returnCode,
    returnMessage: returnMessage,
    info: info,
    orderResult: orderResult,
    error: lpOk ? null : (returnMessage || 'Line Pay offline error')
  };
}

// ===== 手動封存指定月份的已關帳訂單 =====
// 傳入：{ action: "archiveCurrentMonth", month: "2026-04" }（month 可省略，預設當月）
function archiveCurrentMonthOrders_(payload) {
  var ss = SpreadsheetApp.getActive();
  var tz = ss.getSpreadsheetTimeZone();
  var now = new Date();

  var monthStr = (payload && payload.month)
    ? String(payload.month).substring(0, 7)
    : Utilities.formatDate(now, tz, 'yyyy-MM');

  var parts = monthStr.split('-');
  var year  = parseInt(parts[0]);
  var month = parseInt(parts[1]);

  var monthStart = monthStr + '-01';
  var nextYear  = month === 12 ? year + 1 : year;
  var nextMonth = month === 12 ? 1 : month + 1;
  var monthEnd  = Utilities.formatDate(new Date(nextYear, nextMonth - 1, 1), tz, 'yyyy-MM-dd');

  var ordersSheet = ss.getSheetByName('Orders');
  if (!ordersSheet) return { ok: false, error: 'Orders sheet not found' };

  var values = ordersSheet.getDataRange().getValues();
  if (values.length <= 1) {
    return {
      ok: true,
      month: monthStr,
      archivedRows: 0,
      deletedRows: 0,
      archiveSheetName: getArchiveSheetName_(monthStart),
      message: '沒有可封存的資料'
    };
  }

  var header = values[0];
  var idxDate       = header.indexOf('Date');
  var idxCreatedAt  = header.indexOf('CreatedAt');
  var idxStatus     = header.indexOf('Status');
  var idxClosedFlag = header.indexOf('ClosedFlag');

  if (idxClosedFlag < 0) return { ok: false, error: 'Orders 缺少 ClosedFlag 欄位' };
  if (idxDate < 0 && idxCreatedAt < 0) return { ok: false, error: 'Orders 缺少 Date 或 CreatedAt 欄位' };

  var rowsToArchive = [];

  for (var i = 1; i < values.length; i++) {
    var row = values[i];

    var closedUpper = String(row[idxClosedFlag] || '').trim().toUpperCase();
    if (closedUpper !== 'Y') continue;

    var statusUpper = String(idxStatus >= 0 ? row[idxStatus] || '' : '').trim().toUpperCase();
    if (statusUpper !== 'PAID' && statusUpper !== 'CLOSED') continue;

    var dateVal = idxDate >= 0 ? row[idxDate] : (idxCreatedAt >= 0 ? row[idxCreatedAt] : null);
    var rowDateStr = getRowDateStrForArchive_(dateVal, monthStart, tz);
    if (rowDateStr < monthStart) continue;
    if (rowDateStr >= monthEnd) continue;

    rowsToArchive.push(i + 1);
  }

  var archiveResult = archiveAndDeleteClosedPaidOrders_(monthStart, rowsToArchive);

  return {
    ok: archiveResult.ok,
    month: monthStr,
    archivedRows: archiveResult.archivedRows,
    deletedRows: archiveResult.deletedRows,
    archiveSheetName: archiveResult.archiveSheetName,
    message: archiveResult.archivedRows > 0
      ? '已封存 ' + archiveResult.archivedRows + ' 筆至 ' + archiveResult.archiveSheetName
      : '本月沒有符合條件的已關帳資料'
  };
}

/*******************************************************
 * 訂位 CRUD
 *******************************************************/

// 黑名單
function getBlacklist_() {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Blacklist');
  if (!sheet) return { ok: true, phones: [] };
  var values = sheet.getDataRange().getValues();
  if (values.length <= 1) return { ok: true, phones: [] };
  var phones = [];
  for (var i = 1; i < values.length; i++) {
    var p = String(values[i][0] || '').trim();
    if (p) phones.push(p);
  }
  return { ok: true, phones: phones };
}

function addToBlacklist_(data) {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Blacklist');
  if (!sheet) return { ok: false, error: 'Blacklist sheet not found' };
  var phone = String(data.phone || '').trim();
  if (!phone) return { ok: false, error: 'phone is required' };
  // 避免重複
  var values = sheet.getDataRange().getValues();
  for (var i = 1; i < values.length; i++) {
    if (String(values[i][0]).trim() === phone) return { ok: true, message: 'already exists' };
  }
  var tz = ss.getSpreadsheetTimeZone();
  sheet.appendRow([phone, Utilities.formatDate(new Date(), tz, 'yyyy-MM-dd HH:mm:ss')]);
  return { ok: true };
}

// 代理蛋糕網站訂單 API
function getCakeOrders_(from, to) {
  try {
    var baseUrl = 'https://www.nostalgiacoffeeroastery.com/api/pos/orders';
    var url = baseUrl + '?from=' + encodeURIComponent(from) + '&to=' + encodeURIComponent(to);
    var response = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { 'Authorization': 'Bearer nospos2026' },
      muteHttpExceptions: true
    });
    var json = JSON.parse(response.getContentText());
    return json;
  } catch (e) {
    return { ok: false, error: e.message };
  }
}

function getReservations_() {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Reservations');
  if (!sheet) return { ok: true, reservations: [] };

  var values = sheet.getDataRange().getValues();
  if (values.length <= 1) return { ok: true, reservations: [] };

  var header = values[0];
  var idxId       = header.indexOf('ReservationId');
  var idxDate     = header.indexOf('Date');
  var idxTime     = header.indexOf('Time');
  var idxName     = header.indexOf('Name');
  var idxTitle    = header.indexOf('Title');
  var idxPhone    = header.indexOf('Phone');
  var idxAdults   = header.indexOf('Adults');
  var idxChildren = header.indexOf('Children');
  var idxNote     = header.indexOf('Note');
  var idxStatus   = header.indexOf('Status');

  var tz = ss.getSpreadsheetTimeZone();
  var reservations = [];
  for (var i = 1; i < values.length; i++) {
    var row = values[i];
    var id = String(row[idxId] || '').trim();
    if (!id) continue;
    var dateVal = row[idxDate];
    var timeVal = row[idxTime];
    var dateStr = dateVal instanceof Date
      ? Utilities.formatDate(dateVal, tz, 'yyyy-MM-dd')
      : String(dateVal || '');
    var timeStr = timeVal instanceof Date
      ? Utilities.formatDate(timeVal, tz, 'HH:mm')
      : String(timeVal || '');
    reservations.push({
      id:       id,
      date:     dateStr,
      time:     timeStr,
      name:     String(row[idxName]     || ''),
      title:    String(row[idxTitle]    || ''),
      phone:    String(row[idxPhone]    || ''),
      adults:   Number(row[idxAdults])  || 0,
      children: Number(row[idxChildren])|| 0,
      note:     String(row[idxNote]     || ''),
      status:   String(row[idxStatus]   || 'pending')
    });
  }
  return { ok: true, reservations: reservations };
}

function createReservation_(data) {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Reservations');
  if (!sheet) return { ok: false, error: 'Reservations sheet not found' };

  var r = data.reservation || data;
  var id = String(r.id || Utilities.getUuid());
  var now = new Date();
  var tz  = ss.getSpreadsheetTimeZone();

  sheet.appendRow([
    id,
    String(r.date     || ''),
    String(r.time     || ''),
    String(r.name     || ''),
    String(r.title    || ''),
    String(r.phone    || ''),
    Number(r.adults)  || 0,
    Number(r.children)|| 0,
    String(r.note     || ''),
    String(r.status   || 'pending'),
    Utilities.formatDate(now, tz, 'yyyy-MM-dd HH:mm:ss')
  ]);

  return { ok: true, id: id };
}

function updateReservation_(data) {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Reservations');
  if (!sheet) return { ok: false, error: 'Reservations sheet not found' };

  var r = data.reservation || data;
  var id = String(r.id || '').trim();
  if (!id) return { ok: false, error: 'id is required' };

  var values = sheet.getDataRange().getValues();
  var header = values[0];
  var idxId       = header.indexOf('ReservationId');
  var idxDate     = header.indexOf('Date');
  var idxTime     = header.indexOf('Time');
  var idxName     = header.indexOf('Name');
  var idxTitle    = header.indexOf('Title');
  var idxPhone    = header.indexOf('Phone');
  var idxAdults   = header.indexOf('Adults');
  var idxChildren = header.indexOf('Children');
  var idxNote     = header.indexOf('Note');
  var idxStatus   = header.indexOf('Status');

  for (var i = 1; i < values.length; i++) {
    if (String(values[i][idxId] || '').trim() !== id) continue;
    var row = i + 1;
    if (r.date     !== undefined) sheet.getRange(row, idxDate     + 1).setValue(r.date);
    if (r.time     !== undefined) sheet.getRange(row, idxTime     + 1).setValue(r.time);
    if (r.name     !== undefined) sheet.getRange(row, idxName     + 1).setValue(r.name);
    if (r.title    !== undefined) sheet.getRange(row, idxTitle    + 1).setValue(r.title);
    if (r.phone    !== undefined) sheet.getRange(row, idxPhone    + 1).setValue(r.phone);
    if (r.adults   !== undefined) sheet.getRange(row, idxAdults   + 1).setValue(Number(r.adults));
    if (r.children !== undefined) sheet.getRange(row, idxChildren + 1).setValue(Number(r.children));
    if (r.note     !== undefined) sheet.getRange(row, idxNote     + 1).setValue(r.note);
    if (r.status   !== undefined) sheet.getRange(row, idxStatus   + 1).setValue(r.status);
    return { ok: true, id: id };
  }
  return { ok: false, error: 'Reservation not found: ' + id };
}

function deleteReservation_(data) {
  var ss = getPOSSpreadsheet_();
  var sheet = ss.getSheetByName('Reservations');
  if (!sheet) return { ok: false, error: 'Reservations sheet not found' };

  var id = String(data.id || '').trim();
  if (!id) return { ok: false, error: 'id is required' };

  var values = sheet.getDataRange().getValues();
  var header = values[0];
  var idxId = header.indexOf('ReservationId');

  for (var i = 1; i < values.length; i++) {
    if (String(values[i][idxId] || '').trim() !== id) continue;
    sheet.deleteRow(i + 1);
    return { ok: true, id: id };
  }
  return { ok: false, error: 'Reservation not found: ' + id };
}

/*******************************************************
 * 手機網頁介面
 *******************************************************/

function mobilePage_() {
  var gasUrl = ScriptApp.getService().getUrl();
  var html = '<!DOCTYPE html>\n'
    + '<html lang="zh-TW">\n'
    + '<head>\n'
    + '<meta charset="UTF-8">\n'
    + '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">\n'
    + '<meta name="apple-mobile-web-app-capable" content="yes">\n'
    + '<meta name="apple-mobile-web-app-status-bar-style" content="default">\n'
    + '<title>眷鳥 POS</title>\n'
    + '<style>\n'
    + '* { box-sizing: border-box; margin: 0; padding: 0; -webkit-tap-highlight-color: transparent; }\n'
    + 'body { font-family: -apple-system, sans-serif; background: #f2f2f7; color: #1c1c1e; }\n'
    + '.tab-bar { display: flex; background: #fff; border-bottom: 1px solid #e5e5ea; position: sticky; top: 0; z-index: 100; }\n'
    + '.tab-btn { flex: 1; padding: 14px 0; text-align: center; font-size: 15px; font-weight: 600; color: #8e8e93; border: none; background: none; cursor: pointer; border-bottom: 3px solid transparent; }\n'
    + '.tab-btn.active { color: #007aff; border-bottom-color: #007aff; }\n'
    + '.tab-content { display: none; padding: 16px; padding-bottom: 100px; }\n'
    + '.tab-content.active { display: block; }\n'
    + '.section-header { font-size: 13px; font-weight: 600; color: #8e8e93; text-transform: uppercase; letter-spacing: 0.5px; margin: 16px 0 8px; padding: 0 4px; }\n'
    + '.card { background: #fff; border-radius: 12px; padding: 14px 16px; margin-bottom: 10px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }\n'
    + '.card-title { font-size: 16px; font-weight: 600; margin-bottom: 4px; }\n'
    + '.card-sub { font-size: 14px; color: #3c3c43; margin-bottom: 2px; }\n'
    + '.card-note { font-size: 13px; color: #ff9500; margin-top: 4px; }\n'
    + '.card-meta { font-size: 13px; color: #8e8e93; }\n'
    + '.badge { display: inline-block; padding: 2px 8px; border-radius: 10px; font-size: 12px; font-weight: 600; margin-left: 6px; }\n'
    + '.badge-paid { background: #d4edda; color: #1a7a35; }\n'
    + '.badge-pending { background: #fff3cd; color: #856404; }\n'
    + '.status-btns { display: flex; gap: 8px; margin-top: 10px; }\n'
    + '.status-btn { flex: 1; padding: 8px; border-radius: 8px; border: 1.5px solid #e5e5ea; background: #fff; font-size: 14px; font-weight: 600; cursor: pointer; color: #3c3c43; }\n'
    + '.status-btn.arrived { background: #d4edda; border-color: #1a7a35; color: #1a7a35; }\n'
    + '.status-btn.noshow { background: #fde8e8; border-color: #c0392b; color: #c0392b; }\n'
    + '.status-btn.delete-btn { flex: 0 0 auto; padding: 8px 14px; color: #c0392b; border-color: #f5c6cb; }\n'
    + '.fab { position: fixed; bottom: 24px; right: 24px; width: 56px; height: 56px; border-radius: 28px; background: #007aff; color: #fff; font-size: 28px; border: none; box-shadow: 0 4px 12px rgba(0,122,255,0.4); cursor: pointer; display: flex; align-items: center; justify-content: center; z-index: 200; }\n'
    + '.modal-overlay { display: none; position: fixed; inset: 0; background: rgba(0,0,0,0.4); z-index: 300; }\n'
    + '.modal-overlay.open { display: flex; align-items: flex-end; }\n'
    + '.modal { background: #f2f2f7; border-radius: 20px 20px 0 0; width: 100%; max-height: 90vh; overflow-y: auto; padding: 20px 16px 40px; }\n'
    + '.modal-title { font-size: 18px; font-weight: 700; text-align: center; margin-bottom: 20px; }\n'
    + '.form-group { margin-bottom: 14px; }\n'
    + '.form-label { font-size: 13px; color: #8e8e93; font-weight: 600; margin-bottom: 6px; display: block; }\n'
    + '.form-input { width: 100%; padding: 12px 14px; border-radius: 10px; border: 1.5px solid #e5e5ea; font-size: 16px; background: #fff; appearance: none; }\n'
    + '.form-input:focus { outline: none; border-color: #007aff; }\n'
    + '.title-btns { display: flex; gap: 8px; }\n'
    + '.title-btn { flex: 1; padding: 10px; border-radius: 8px; border: 1.5px solid #e5e5ea; background: #fff; font-size: 15px; cursor: pointer; }\n'
    + '.title-btn.selected { background: #007aff; border-color: #007aff; color: #fff; }\n'
    + '.row-btns { display: flex; gap: 8px; }\n'
    + '.count-btn { width: 36px; height: 36px; border-radius: 18px; border: 1.5px solid #007aff; background: #fff; color: #007aff; font-size: 20px; cursor: pointer; display: flex; align-items: center; justify-content: center; }\n'
    + '.count-val { font-size: 18px; font-weight: 600; width: 36px; text-align: center; line-height: 36px; }\n'
    + '.submit-btn { width: 100%; padding: 16px; border-radius: 12px; background: #007aff; color: #fff; font-size: 17px; font-weight: 700; border: none; cursor: pointer; margin-top: 8px; }\n'
    + '.submit-btn:disabled { background: #c7c7cc; }\n'
    + '.cancel-btn { width: 100%; padding: 14px; border-radius: 12px; background: #fff; color: #ff3b30; font-size: 17px; font-weight: 600; border: none; cursor: pointer; margin-top: 8px; }\n'
    + '.loading { text-align: center; padding: 40px; color: #8e8e93; font-size: 15px; }\n'
    + '.empty { text-align: center; padding: 40px; color: #c7c7cc; font-size: 15px; }\n'
    + '.refresh-btn { display: flex; align-items: center; justify-content: center; gap: 6px; width: 100%; padding: 10px; background: #fff; border: none; border-radius: 10px; font-size: 14px; color: #007aff; font-weight: 600; cursor: pointer; margin-bottom: 12px; }\n'
    + '</style>\n'
    + '</head>\n'
    + '<body>\n'
    + '<div class="tab-bar">\n'
    + '  <button class="tab-btn active" onclick="showTab(\'orders\')">蛋糕訂單</button>\n'
    + '  <button class="tab-btn" onclick="showTab(\'reservations\')">訂位</button>\n'
    + '</div>\n'
    + '\n'
    + '<div id="tab-orders" class="tab-content active">\n'
    + '  <button class="refresh-btn" onclick="loadOrders()">↻ 重新整理</button>\n'
    + '  <div id="orders-list"><div class="loading">載入中…</div></div>\n'
    + '</div>\n'
    + '\n'
    + '<div id="tab-reservations" class="tab-content">\n'
    + '  <button class="refresh-btn" onclick="loadReservations()">↻ 重新整理</button>\n'
    + '  <div id="res-list"><div class="loading">載入中…</div></div>\n'
    + '</div>\n'
    + '\n'
    + '<div id="tab-reservations-fab" style="display:none">\n'
    + '  <button class="fab" onclick="openAddModal()" title="新增訂位">＋</button>\n'
    + '</div>\n'
    + '\n'
    + '<div class="modal-overlay" id="add-modal">\n'
    + '  <div class="modal">\n'
    + '    <div class="modal-title">新增訂位</div>\n'
    + '    <div class="form-group">\n'
    + '      <label class="form-label">姓名</label>\n'
    + '      <input class="form-input" id="f-name" type="text" placeholder="請輸入姓名">\n'
    + '    </div>\n'
    + '    <div class="form-group">\n'
    + '      <label class="form-label">稱謂</label>\n'
    + '      <div class="title-btns">\n'
    + '        <button class="title-btn selected" id="title-none" onclick="setTitle(\'\')">無</button>\n'
    + '        <button class="title-btn" id="title-mr" onclick="setTitle(\'先生\')">先生</button>\n'
    + '        <button class="title-btn" id="title-ms" onclick="setTitle(\'小姐\')">小姐</button>\n'
    + '      </div>\n'
    + '    </div>\n'
    + '    <div class="form-group">\n'
    + '      <label class="form-label">電話</label>\n'
    + '      <input class="form-input" id="f-phone" type="tel" placeholder="請輸入電話">\n'
    + '    </div>\n'
    + '    <div class="form-group">\n'
    + '      <label class="form-label">日期</label>\n'
    + '      <input class="form-input" id="f-date" type="date">\n'
    + '    </div>\n'
    + '    <div class="form-group">\n'
    + '      <label class="form-label">時間</label>\n'
    + '      <input class="form-input" id="f-time" type="time">\n'
    + '    </div>\n'
    + '    <div class="form-group">\n'
    + '      <label class="form-label">大人</label>\n'
    + '      <div class="row-btns">\n'
    + '        <button class="count-btn" onclick="changeCount(\'adults\',-1)">−</button>\n'
    + '        <div class="count-val" id="adults-val">1</div>\n'
    + '        <button class="count-btn" onclick="changeCount(\'adults\',1)">＋</button>\n'
    + '      </div>\n'
    + '    </div>\n'
    + '    <div class="form-group">\n'
    + '      <label class="form-label">小孩</label>\n'
    + '      <div class="row-btns">\n'
    + '        <button class="count-btn" onclick="changeCount(\'children\',-1)">−</button>\n'
    + '        <div class="count-val" id="children-val">0</div>\n'
    + '        <button class="count-btn" onclick="changeCount(\'children\',1)">＋</button>\n'
    + '      </div>\n'
    + '    </div>\n'
    + '    <div class="form-group">\n'
    + '      <label class="form-label">備註</label>\n'
    + '      <input class="form-input" id="f-note" type="text" placeholder="選填">\n'
    + '    </div>\n'
    + '    <button class="submit-btn" id="submit-btn" onclick="submitReservation()">確認新增</button>\n'
    + '    <button class="cancel-btn" onclick="closeModal()">取消</button>\n'
    + '  </div>\n'
    + '</div>\n'
    + '\n'
    + '<script>\n'
    + 'var GAS_URL = "' + gasUrl + '";\n'
    + 'var selectedTitle = "";\n'
    + 'var adults = 1, children = 0;\n'
    + '\n'
    + 'function showTab(tab) {\n'
    + '  document.querySelectorAll(".tab-btn").forEach(function(b,i){\n'
    + '    b.classList.toggle("active", (i===0&&tab==="orders")||(i===1&&tab==="reservations"));\n'
    + '  });\n'
    + '  document.getElementById("tab-orders").classList.toggle("active", tab==="orders");\n'
    + '  document.getElementById("tab-reservations").classList.toggle("active", tab==="reservations");\n'
    + '  document.getElementById("tab-reservations-fab").style.display = tab==="reservations" ? "block" : "none";\n'
    + '  if (tab==="orders") loadOrders();\n'
    + '  if (tab==="reservations") loadReservations();\n'
    + '}\n'
    + '\n'
    + 'function gasGet(action) {\n'
    + '  return fetch(GAS_URL + "?action=" + action).then(function(r){return r.json();});\n'
    + '}\n'
    + 'function gasPost(body) {\n'
    + '  return fetch(GAS_URL, {method:"POST",body:JSON.stringify(body)}).then(function(r){return r.json();});\n'
    + '}\n'
    + '\n'
    + 'function loadOrders() {\n'
    + '  document.getElementById("orders-list").innerHTML = \'<div class="loading">載入中…</div>\';\n'
    + '  var today = new Date();\n'
    + '  var future = new Date(today); future.setDate(future.getDate() + 14);\n'
    + '  function fmt(d){ return d.toISOString().substring(0,10); }\n'
    + '  var url = GAS_URL + "?action=getCakeOrders&from=" + fmt(today) + "&to=" + fmt(future);\n'
    + '  fetch(url).then(function(r){return r.json();}).then(function(res) {\n'
    + '    var orders = (res.orders || []);\n'
    + '    if (!orders.length) { document.getElementById("orders-list").innerHTML = \'<div class="empty">近 14 天無蛋糕訂單</div>\'; return; }\n'
    + '    orders.sort(function(a,b){ return (a.pickupDate+a.pickupTime)<(b.pickupDate+b.pickupTime)?-1:1; });\n'
    + '    var html = "";\n'
    + '    orders.forEach(function(o) {\n'
    + '      var items = (o.items||[]).map(function(it){return it.name+"×"+it.quantity;}).join("、");\n'
    + '      html += \'<div class="card">\';\n'
    + '      html += \'<div class="card-title">\' + (o.customer||"—") + \'<span style="font-size:12px;color:#8e8e93;font-weight:400;margin-left:8px;">\' + (o.orderNo||"") + "</span></div>";\n'
    + '      html += \'<div class="card-sub">取貨：\' + (o.pickupDate||"—") + " " + (o.pickupTime||"") + "　NT$" + (o.totalAmount||0) + "</div>";\n'
    + '      if (o.phone) html += \'<div class="card-meta">📞 \' + o.phone + "</div>";\n'
    + '      if (items) html += \'<div class="card-meta">\' + items + "</div>";\n'
    + '      if (o.note) html += \'<div class="card-note">\' + o.note + "</div>";\n'
    + '      html += "</div>";\n'
    + '    });\n'
    + '    document.getElementById("orders-list").innerHTML = html;\n'
    + '  }).catch(function(){ document.getElementById("orders-list").innerHTML = \'<div class="empty">載入失敗</div>\'; });\n'
    + '}\n'
    + '\n'
    + 'var blacklistPhones = [];\n'
    + 'fetch(GAS_URL + "?action=getBlacklist").then(function(r){return r.json();}).then(function(res){ blacklistPhones = res.phones || []; }).catch(function(){});\n'
    + '\n'
    + 'var allReservations = [];\n'
    + 'function loadReservations() {\n'
    + '  document.getElementById("res-list").innerHTML = \'<div class="loading">載入中…</div>\';\n'
    + '  gasGet("getReservations").then(function(res) {\n'
    + '    allReservations = res.reservations || [];\n'
    + '    renderReservations();\n'
    + '  }).catch(function(){ document.getElementById("res-list").innerHTML = \'<div class="empty">載入失敗</div>\'; });\n'
    + '}\n'
    + '\n'
    + 'function renderReservations() {\n'
    + '  var today = new Date(); today.setHours(0,0,0,0);\n'
    + '  var cutoff = new Date(today); cutoff.setDate(cutoff.getDate() + 30);\n'
    + '  var cutoffStr = cutoff.toISOString().substring(0,10);\n'
    + '  var todayStr = today.toISOString().substring(0,10);\n'
    + '  var upcoming = allReservations\n'
    + '    .filter(function(r){ return r.date >= todayStr && r.date <= cutoffStr; })\n'
    + '    .sort(function(a,b){ return (a.date+a.time) < (b.date+b.time) ? -1 : 1; });\n'
    + '  if (!upcoming.length) { document.getElementById("res-list").innerHTML = \'<div class="empty">未來 30 天無訂位</div>\'; return; }\n'
    + '  var byDate = {};\n'
    + '  upcoming.forEach(function(r){ if (!byDate[r.date]) byDate[r.date]=[]; byDate[r.date].push(r); });\n'
    + '  var html = "";\n'
    + '  Object.keys(byDate).sort().forEach(function(date) {\n'
    + '    var d = new Date(date + "T00:00:00");\n'
    + '    var days = ["日","一","二","三","四","五","六"];\n'
    + '    var label = (d.getMonth()+1) + "/" + d.getDate() + "（" + days[d.getDay()] + "）";\n'
    + '    html += \'<div class="section-header">\' + label + "</div>";\n'
    + '    byDate[date].forEach(function(r) {\n'
    + '      var statusClass = r.status === "arrived" ? "arrived" : r.status === "noShow" ? "noshow" : "";\n'
    + '      html += \'<div class="card" id="res-\' + r.id + \'">\' ;\n'
    + '      html += \'<div class="card-title">\' + r.time + "　" + r.name + r.title + "</div>";\n'
    + '      html += \'<div class="card-sub">大人 \' + r.adults + "・小孩 " + r.children + "</div>";\n'
    + '      if (r.phone) html += \'<div class="card-meta">\' + r.phone + "</div>";\n'
    + '      if (r.note)  html += \'<div class="card-note">\' + r.note  + "</div>";\n'
    + '      html += \'<div class="status-btns">\';\n'
    + '      html += \'<button class="status-btn \' + (r.status==="arrived"?"arrived":"") + \'" onclick="setStatus(\\\'\' + r.id + \'\\\',\\\'arrived\\\')">到達</button>\';\n'
    + '      html += \'<button class="status-btn \' + (r.status==="noShow"?"noshow":"") + \'" onclick="setStatus(\\\'\' + r.id + \'\\\',\\\'noShow\\\')">No Show</button>\';\n'
    + '      html += \'<button class="status-btn delete-btn" onclick="deleteReservation(\\\'\' + r.id + \'\\\')">刪除</button>\';\n'
    + '      html += "</div></div>";\n'
    + '    });\n'
    + '  });\n'
    + '  document.getElementById("res-list").innerHTML = html;\n'
    + '}\n'
    + '\n'
    + 'function setStatus(id, status) {\n'
    + '  var r = allReservations.find(function(x){return x.id===id;});\n'
    + '  if (!r) return;\n'
    + '  var newStatus = r.status === status ? "pending" : status;\n'
    + '  r.status = newStatus;\n'
    + '  renderReservations();\n'
    + '  gasPost({action:"updateReservation", reservation:{id:id, status:newStatus}});\n'
    + '}\n'
    + 'function deleteReservation(id) {\n'
    + '  if (!confirm("確定要刪除這筆訂位嗎？")) return;\n'
    + '  allReservations = allReservations.filter(function(x){return x.id!==id;});\n'
    + '  renderReservations();\n'
    + '  gasPost({action:"deleteReservation", id:id});\n'
    + '}\n'
    + '\n'
    + 'function openAddModal() {\n'
    + '  var today = new Date().toISOString().substring(0,10);\n'
    + '  document.getElementById("f-date").value = today;\n'
    + '  document.getElementById("f-time").value = "";\n'
    + '  document.getElementById("f-name").value = "";\n'
    + '  document.getElementById("f-phone").value = "";\n'
    + '  document.getElementById("f-note").value = "";\n'
    + '  adults = 1; children = 0;\n'
    + '  document.getElementById("adults-val").textContent = "1";\n'
    + '  document.getElementById("children-val").textContent = "0";\n'
    + '  setTitle("");\n'
    + '  document.getElementById("add-modal").classList.add("open");\n'
    + '}\n'
    + 'function closeModal() {\n'
    + '  document.getElementById("add-modal").classList.remove("open");\n'
    + '}\n'
    + 'function setTitle(t) {\n'
    + '  selectedTitle = t;\n'
    + '  ["none","mr","ms"].forEach(function(k){\n'
    + '    var map = {"none":"","mr":"先生","ms":"小姐"};\n'
    + '    document.getElementById("title-"+k).classList.toggle("selected", map[k]===t);\n'
    + '  });\n'
    + '}\n'
    + 'function changeCount(field, delta) {\n'
    + '  if (field==="adults") { adults = Math.max(0, adults+delta); document.getElementById("adults-val").textContent = adults; }\n'
    + '  else { children = Math.max(0, children+delta); document.getElementById("children-val").textContent = children; }\n'
    + '}\n'
    + 'function generateUUID() {\n'
    + '  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c){\n'
    + '    var r = Math.random()*16|0, v = c==="x"?r:(r&0x3|0x8); return v.toString(16);\n'
    + '  });\n'
    + '}\n'
    + 'function submitReservation() {\n'
    + '  var name = document.getElementById("f-name").value.trim();\n'
    + '  var date = document.getElementById("f-date").value;\n'
    + '  var time = document.getElementById("f-time").value;\n'
    + '  var phone = document.getElementById("f-phone").value.trim();\n'
    + '  if (!name || !date || !time || (adults + children) === 0) {\n'
    + '    alert("請填寫姓名、日期、時間，並至少選 1 位客人"); return;\n'
    + '  }\n'
    + '  if (phone && blacklistPhones.indexOf(phone) !== -1) {\n'
    + '    if (!confirm("⚠️ 此號碼（" + phone + "）為黑名單對象，確定要新增訂位嗎？")) return;\n'
    + '  }\n'
    + '  var btn = document.getElementById("submit-btn");\n'
    + '  btn.disabled = true; btn.textContent = "送出中…";\n'
    + '  var r = {\n'
    + '    id: generateUUID(),\n'
    + '    date: date,\n'
    + '    time: time,\n'
    + '    name: name,\n'
    + '    title: selectedTitle,\n'
    + '    phone: document.getElementById("f-phone").value.trim(),\n'
    + '    adults: adults,\n'
    + '    children: children,\n'
    + '    note: document.getElementById("f-note").value.trim(),\n'
    + '    status: "pending"\n'
    + '  };\n'
    + '  gasPost({action:"createReservation", reservation:r}).then(function(res){\n'
    + '    btn.disabled = false; btn.textContent = "確認新增";\n'
    + '    if (res.ok) { closeModal(); allReservations.push(r); renderReservations(); }\n'
    + '    else alert("新增失敗：" + (res.error||"未知錯誤"));\n'
    + '  }).catch(function(){ btn.disabled=false; btn.textContent="確認新增"; alert("網路錯誤"); });\n'
    + '}\n'
    + '\n'
    + 'document.getElementById("add-modal").addEventListener("click", function(e){\n'
    + '  if (e.target === this) closeModal();\n'
    + '});\n'
    + '\n'
    + 'loadOrders();\n'
    + 'setInterval(function(){\n'
    + '  var activeTab = document.querySelector(".tab-content.active");\n'
    + '  if (activeTab && activeTab.id === "tab-orders") loadOrders();\n'
    + '  else loadReservations();\n'
    + '}, 60000);\n'
    + '</script>\n'
    + '</body>\n'
    + '</html>';

  return HtmlService.createHtmlOutput(html)
    .setTitle('眷鳥 POS')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1, maximum-scale=1');
}
