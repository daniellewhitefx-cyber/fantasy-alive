// Google Apps Script Web App that receives event registrations from
// register.html and writes them into "Fantasy Alive — Registrations".
//
// This file is not deployed by git/Vercel — it only runs inside Google's
// Apps Script editor. It's kept here so the logic is version-controlled
// and easy to find. See the setup steps given alongside this file for how
// to paste it in and deploy it.
//
// For each event date, this creates (on first use) a "<date> - Roster"
// tab listing everyone registered, and a "<date> - Kitchen" tab listing
// only people who selected a meal, with blank checkbox cells for the
// meals they're actually getting, meant to be printed and marked off.

var SHEET_ID = '1QJQj1j4bTUrvIdQZvdTPhFN_ncGcXKvOmSPUvoULLk4';
var MEAL_SLOT_COLUMNS = ['Saturday Breakfast', 'Saturday Lunch', 'Saturday Dinner', 'Sunday Breakfast'];

function doPost(e) {
  var body = JSON.parse(e.postData.contents);
  var ss = SpreadsheetApp.openById(SHEET_ID);

  appendToRoster(ss, body);
  appendToKitchen(ss, body);

  return ContentService
    .createTextOutput(JSON.stringify({ ok: true }))
    .setMimeType(ContentService.MimeType.JSON);
}

// Lets the site ask "has this player already registered this
// character (or Cast) for this event?" so register.html and
// characters.html can show a "You're Registered!" state instead of
// letting someone sign up twice.
//
// Expected query params: ?action=check&event=<event label>
//   &who=character|cast&character=<character name, or "Cast">&email=<player email>
function doGet(e) {
  var params = e.parameter;

  if (params.action !== 'check') {
    return jsonOutput({ error: 'Unknown action' });
  }

  var ss = SpreadsheetApp.openById(SHEET_ID);
  var sheet = ss.getSheetByName(params.event + ' - Roster');
  if (!sheet) {
    return jsonOutput({ registered: false });
  }

  var data = sheet.getDataRange().getValues();
  var header = data[0];
  var emailCol = header.indexOf('Player Email');
  var charCol = header.indexOf('Character / Cast');

  var wantEmail = (params.email || '').toLowerCase();
  var wantCharacter = params.character || (params.who === 'cast' ? 'Cast' : '');

  for (var i = 1; i < data.length; i++) {
    var row = data[i];
    var rowEmail = (row[emailCol] || '').toString().toLowerCase();
    var rowCharacter = (row[charCol] || '').toString();

    if (rowEmail === wantEmail && rowCharacter === wantCharacter) {
      return jsonOutput({
        registered: true,
        registration: {
          passName: row[header.indexOf('Pass')],
          combatStatus: row[header.indexOf('Combat Status')],
          daysAttending: row[header.indexOf('Days Attending')],
          mealName: row[header.indexOf('Meal Plan')],
          total: row[header.indexOf('Total')]
        }
      });
    }
  }

  return jsonOutput({ registered: false });
}

function jsonOutput(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function appendToRoster(ss, body) {
  var sheetName = body.eventLabel + ' - Roster';
  var sheet = ss.getSheetByName(sheetName);
  if (!sheet) {
    sheet = ss.insertSheet(sheetName);
    sheet.appendRow([
      'Timestamp', 'Player Email', 'Player Name', 'Character / Cast',
      'Pass', 'Price', 'Combat Status', 'Days Attending',
      'Meal Plan', 'Meal Price', 'Single Meal Choice', 'Total'
    ]);
    sheet.setFrozenRows(1);
  }
  sheet.appendRow([
    new Date(),
    body.playerEmail || '',
    body.playerName || '',
    body.characterName || '',
    body.passName || '',
    body.passPrice || 0,
    body.combatStatus || '',
    (body.daysAttending || []).join(', '),
    body.mealName || 'None',
    body.mealPrice || 0,
    body.singleMealChoice || '',
    body.total || 0
  ]);
}

function appendToKitchen(ss, body) {
  var mealSlots = body.mealSlots || {};
  var hasMeal = MEAL_SLOT_COLUMNS.some(function (slot) { return !!mealSlots[slot]; });
  if (!hasMeal) return; // nobody eating, don't clutter the kitchen sheet

  var sheetName = body.eventLabel + ' - Kitchen';
  var sheet = ss.getSheetByName(sheetName);
  if (!sheet) {
    sheet = ss.insertSheet(sheetName);
    sheet.appendRow(['Name'].concat(MEAL_SLOT_COLUMNS));
    sheet.setFrozenRows(1);
  }
  var row = [body.characterName || body.playerName || ''];
  MEAL_SLOT_COLUMNS.forEach(function (slot) {
    row.push(mealSlots[slot] ? '☐' : ''); // ☐, ticked off by hand at the event
  });
  sheet.appendRow(row);
}
