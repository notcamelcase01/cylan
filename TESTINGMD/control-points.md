[← Back to TESTING.md](../TESTING.md)

# Control points

Personal pins on a route. Most of this is **manual only** — placing a point
means tapping a real map, and the point of the feature is that it survives an
app restart.

The one thing to keep in mind while testing: control points are **local to the
device and never uploaded**. Two accounts on one device share nothing (they're
keyed by ride, not user); the same account on two devices shares nothing
either. Neither is a bug.

### Adding — on the map
- [ ] Open any ride with a GPS track → a **Control points** card shows below the
      route, empty, explaining they're yours alone.
- [ ] **Add → Pick on the map** → a full-screen map opens with the route drawn.
- [ ] Tap the route → a pin drops, and the hint reads "At *X* km along the
      route".
- [ ] Tap elsewhere → the pin moves and the distance updates (it doesn't add a
      second pin).
- [ ] **Use this spot** → the name/type sheet opens showing "At *X* km, picked
      on the map" instead of a distance field.
- [ ] Pick a type, leave the name blank, **Add** → the point is added, named
      after its type.
- [ ] The pin appears on the ride's own map, in the type's colour.

### Adding — by distance
- [ ] **Add → By distance along route** → the sheet opens with an editable
      distance field, helper text showing the ride's `0 – N km` range.
- [ ] Enter a distance beyond the ride's length → an inline error; nothing is
      added.
- [ ] Enter a non-number / leave it blank → an inline error, no crash.
- [ ] Enter a valid distance → the point lands **on the route line** at roughly
      that distance, not off to one side.

### Listing, editing, deleting
- [ ] Add points out of order (e.g. km 30 then km 5) → the list shows them in
      **route order**, each with its type and distance.
- [ ] Tap a row → the editor opens pre-filled; change the name and type → the
      row and the map pin both update.
- [ ] Edit a point's distance → the pin **moves** along the route and the list
      re-sorts.
- [ ] Delete a point → confirm dialog naming it → it's gone from both list and
      map, with a snackbar.
- [ ] **Force-quit and reopen the app** → every point is still there, with its
      name, type and position.

### On other people's rides
- [ ] Open a ride you don't own (Explore, or a public event's route) → the
      control points card is there and fully usable.
- [ ] Add a point → it saves. Confirm the ride's **owner** doesn't see it (sign
      in as them, or check the ride on another device/account).

### Live tracking
- [ ] Start live tracking on a ride that has control points → the pins show on
      the live map in their colours.
- [ ] There's no way to add/edit/delete from the live screen — read-only by
      design.

### Offline
Nothing here needs a connection — put the device in airplane mode for all of it.

- [ ] Add control points to a ride, then save it offline → open it from
      **Offline rides**: the pins are on the map and the card lists them.
- [ ] Add a new point while offline (both methods) → it saves. The picker map
      shows the route as a plain line with no street tiles, and doesn't hang
      waiting for them.
- [ ] Edit and delete points offline → both work.
- [ ] **Live** from the offline ride → the pins show on the live map.
- [ ] Go back online and open the same ride from **My Rides** → every offline
      change is there (it's one store, not two).

### Publishing points — as the organiser
- [ ] Create/edit an event **with no ride attached** → no control points button
      appears.
- [ ] Attach a ride → an **Add control points** button appears under Route.
- [ ] Tap it → the route map and an empty list; add points by both methods.
- [ ] **Done**, then **leave the event form without saving** → reopen the event:
      the points were *not* saved. (Edits only commit with the event.)
- [ ] Add points → **Done** → **Save** → reopen the event editor: the button
      now reads "*N* control points" and the points are there.
- [ ] Remove the attached ride → the points are cleared with it.
- [ ] Delete every point → **Save** → reopen: they're really gone (the field is
      always sent, so clearing works).
- [ ] As a **different** user, open the event → the points show under
      **Organiser's control points**. If they don't, the API isn't storing them
      — check the deploy before anything else.

### Importing — as a rider
Nothing is ever added to your route automatically. That's the whole design:
a route can back many events, so the app never guesses which event you meant.

- [ ] Open an event with control points → they're listed read-only under
      **Organiser's control points**, *without* being added to your route. This
      matters: an organiser's "caution" marker has to reach you either way.
- [ ] **View route** → the organiser's pins show on the map, but the
      **Control points** card below is still empty (they're not yours yet).
- [ ] Back on the event, tap **Add to my control points** → a confirmation
      snackbar; open the route → they're now in your card too.
- [ ] Each imported row reads "*the organiser's*" and shows a **lock** icon
      instead of a delete button. Tapping the row does **not** open the editor.
- [ ] Your own points on that route are untouched, and still fully editable.
- [ ] Reopen the event → the button now reads **Remove from my route**; the
      organiser's pins are no longer drawn twice on the route map.
- [ ] Tap **Remove from my route** → confirm → the imported points go; your own
      remain; the button reverts to **Add to my control points**.

### Two events, one route — the case this design exists for
- [ ] Have two events (ideally two different organisers) attach the **same**
      ride, each with different control points.
- [ ] Import **both** → your route shows both sets, and nothing was overwritten.
- [ ] Remove one event's points → the other event's points and your own are
      **untouched**, and only that event's button re-arms.
- [ ] Move back and forth between the two event screens, opening the route each
      time → your control points never change on their own.

### Organiser edits after you've imported
- [ ] Import an event's points, then (as the organiser) change one of them and
      save.
- [ ] As the rider, reopen → your imported copies are **unchanged**. They're
      yours now; there's no push. Picking up the new list means **Remove from
      my route**, then **Add to my control points** again.
- [ ] As the organiser, swap the event's route entirely → your imported points
      stay where they were (they're plain coordinates on your copy). Remove and
      re-add to get points that match the new route.

### Edge cases
- [ ] Open a ride with **no GPS track** → no control points card at all, no
      crash.
- [ ] Open an event whose organiser set no control points → no
      **Organiser's control points** section at all; your own card still works.
- [ ] Import an event whose route has no GPS track → a clear message, not a
      crash or a silent no-op.
- [ ] Delete every imported point's *event* while offline → the import button
      still works from cached event data, or fails with a readable message.
- [ ] Add a point on a route that **crosses itself** (a loop or out-and-back) →
      it lands where you tapped. Its *distance* reading may pick the wrong pass
      — known limitation (nearest sample, not perpendicular projection).

