'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';
'require rpc';
'require request';

var MFW = '/usr/sbin/multifw';
var UPLOAD = '/tmp/multifw-upload.itb';

function mib(n) { return n ? (n / 1048576).toFixed(1) + ' MiB' : '-'; }

function mfwStatus() {
	return fs.exec(MFW, [ 'status' ]).then(function(r) {
		try { return JSON.parse(r.stdout); } catch (e) { return null; }
	}).catch(function() { return null; });
}

function mfw(args, msg) {
	return fs.exec(MFW, args).then(function(r) {
		if (r.code !== 0)
			throw new Error((r.stderr || r.stdout || '').trim() || ('exit ' + r.code));
		if (msg) ui.addNotification(null, E('p', msg), 'info');
		return r;
	}).catch(function(e) {
		ui.addNotification(null, E('p', _('Error: %s').format(e.message)), 'danger');
		throw e;
	});
}

function reload() { location.reload(); }

return view.extend({
	load: function() {
		return Promise.all([ uci.load('wireless'), mfwStatus() ]);
	},

	/* "Through-wall" = maximise reach within the regulatory limit:
	 * no tx power cap (driver uses the regdomain maximum), 20 MHz on 2.4 GHz
	 * (better SNR at range), beamforming on, keep weak clients associated. */
	applyPreset: function(mode) {
		uci.sections('wireless', 'wifi-device').forEach(function(r) {
			var s = r['.name'], band = r.band;
			[ 'su_beamformer', 'mu_beamformer', 'he_su_beamformer', 'he_mu_beamformer', 'he_su_beamformee' ]
				.forEach(function(o) { uci.unset('wireless', s, o); });   /* defaults are "on" */
			if (mode === 'wall') {
				uci.unset('wireless', s, 'txpower');
				uci.set('wireless', s, 'cell_density', '0');
				if (band === '2g') uci.set('wireless', s, 'htmode', 'HE20');
			} else {
				uci.unset('wireless', s, 'cell_density');
				if (band === '2g') uci.set('wireless', s, 'htmode', 'HE20');
			}
		});
		uci.sections('wireless', 'wifi-iface').forEach(function(r) {
			if (mode === 'wall')
				uci.set('wireless', r['.name'], 'disassoc_low_ack', '0');
			else
				uci.unset('wireless', r['.name'], 'disassoc_low_ack');
		});
		return uci.save().then(function() { return ui.changes.apply(true); });
	},

	confirmBoot: function(slot) {
		ui.showModal(_('Boot another firmware'), [
			E('p', _('Reboot into the firmware in %s? The firmware running now moves into that slot and can be booted back at any time.').format(slot.label)),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
				E('button', { 'class': 'btn cbi-button-negative', 'click': function() {
					mfw([ 'boot', slot.id ]).then(function() {
						ui.showModal(_('Rebooting…'), E('p', { 'class': 'spinning' }, _('Switching firmware, reconnect in about 90 seconds.')));
					});
				} }, _('Boot it'))
			])
		]);
	},

	flashSlot: function(slot, ev) {
		var input = E('input', { 'type': 'file', 'accept': '.itb,.bin' });
		input.addEventListener('change', function() {
			var file = input.files[0];
			if (!file) return;
			var name = file.name.replace(/\.(itb|bin)$/, '').replace(/-squashfs-sysupgrade$/, '').replace(/-mediatek-filogic-viettel_32x6$/, '');
			var body = new FormData();
			body.append('sessionid', rpc.getSessionID());
			body.append('filename', UPLOAD);
			body.append('filedata', file);
			ui.showModal(_('Writing firmware…'), E('p', { 'class': 'spinning' }, _('Uploading and writing %s, do not power off.').format(file.name)));
			request.post(L.env.cgi_base + '/cgi-upload', body, { timeout: 0 }).then(function(res) {
				if (!res.ok) throw new Error(res.statusText || 'upload failed');
				return mfw([ 'flash', slot.id, UPLOAD, '--name', name ], _('Firmware written to %s.').format(slot.label));
			}).then(function() { return fs.remove(UPLOAD); })
			  .catch(function() {})
			  .finally(function() { ui.hideModal(); reload(); });
		});
		input.click();
	},

	renderSlots: function(st) {
		var self = this,
		    box = E('div', { 'class': 'cbi-section' }, [ E('h3', _('Multi Firmware')) ]);

		if (!st) {
			box.appendChild(E('p', _('Multi Firmware is unavailable (multi-firmware not installed or UBI not attached).')));
			return box;
		}

		if (st.rolled_back)
			box.appendChild(E('div', { 'class': 'alert-message warning' }, [
				_('The last upgrade did not boot; U-Boot went back to the previous firmware. The failed one is now in the spare slot.'), ' ',
				E('button', { 'class': 'btn', 'click': function() { mfw([ 'clear-rollback' ]).then(reload); } }, _('Dismiss'))
			]));
		if (st.boot_trial)
			box.appendChild(E('div', { 'class': 'alert-message notice' },
				_('This firmware is on trial after an upgrade; it is confirmed about 60 s after boot.')));
		if (st.pending)
			box.appendChild(E('div', { 'class': 'alert-message notice' }, [
				_('Slot %s will boot at the next restart.').format(st.pending), ' ',
				E('button', { 'class': 'btn', 'click': function() { mfw([ 'cancel' ]).then(reload); } }, _('Cancel'))
			]));

		var labels = { '1': _('Running'), '2': _('Slot 2'), 'spare': _('Spare') };
		var rows = [ E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, _('Slot')), E('th', { 'class': 'th' }, _('Firmware')),
			E('th', { 'class': 'th' }, _('Image')), E('th', { 'class': 'th' }, _('Settings')),
			E('th', { 'class': 'th cbi-section-actions' }, '')
		]) ];

		st.slots.forEach(function(sl) {
			sl.label = labels[sl.id] || sl.id;
			var actions = [];
			if (sl.id !== '1' && sl.image)
				actions.push(E('button', { 'class': 'btn cbi-button-action', 'click': function() { self.confirmBoot(sl); } }, _('Boot')));
			if (sl.id === '2')
				actions.push(E('button', { 'class': 'btn', 'click': function(ev) { self.flashSlot(sl, ev); } }, sl.image ? _('Replace…') : _('Load…')));
			if (sl.image)
				actions.push(E('button', { 'class': 'btn', 'click': function() {
					ui.showModal(_('Rename'), [
						E('input', { 'class': 'cbi-input-text', 'id': 'mfw-name', 'value': sl.name || '' }),
						E('div', { 'class': 'right' }, [
							E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
							E('button', { 'class': 'btn cbi-button-positive', 'click': function() {
								mfw([ 'name', sl.id, document.getElementById('mfw-name').value ]).then(reload);
							} }, _('Save'))
						])
					]);
				} }, _('Rename')));
			if (sl.id !== '1' && sl.image)
				actions.push(E('button', { 'class': 'btn cbi-button-negative', 'click': function() {
					ui.showModal(_('Delete'), [
						E('p', _('Delete the firmware and settings stored in %s?').format(sl.label)),
						E('div', { 'class': 'right' }, [
							E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')), ' ',
							E('button', { 'class': 'btn cbi-button-negative', 'click': function() { mfw([ 'delete', sl.id ]).then(reload); } }, _('Delete'))
						])
					]);
				} }, _('Delete')));

			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, sl.label),
				E('td', { 'class': 'td' }, sl.image ? (sl.name || '?') : E('em', _('empty'))),
				E('td', { 'class': 'td' }, mib(sl.image)),
				E('td', { 'class': 'td' }, mib(sl.data)),
				E('td', { 'class': 'td cbi-section-actions' }, E('div', {}, actions))
			]));
		});
		rows.push(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, _('Recovery')),
			E('td', { 'class': 'td' }, st.recovery ? _('initramfs (fallback)') : E('em', _('empty'))),
			E('td', { 'class': 'td' }, mib(st.recovery)), E('td', { 'class': 'td' }, '-'), E('td', { 'class': 'td' }, '')
		]));
		box.appendChild(E('table', { 'class': 'table' }, rows));

		box.appendChild(E('p', _('Free space: %s. Settings of slot 2 are limited to %s; OpenWrt gets the rest of the space at each upgrade. Holding the mesh/WPS button while powering on always boots OpenWrt (no serial console needed).')
			.format(mib(st.free), mib(st.data_max))));

		box.appendChild(E('p', { 'class': 'cbi-value-description' },
			_('A firmware upgrade keeps the running OpenWrt in the spare slot with a backup of its configuration (installed packages are not kept) and goes back to it automatically if the new one fails to boot 3 times. Slot 2 is never touched by an upgrade; loading a firmware into it replaces the old one.')));
		return box;
	},

	render: function(data) {
		var st = data[1], self = this, m, s, o;

		m = new form.Map('wireless', _('Advanced'),
			_('Radio options that are spread over several LuCI pages, plus Multi Firmware. Tx power is always capped by the regulatory domain of the selected country; stay within your local regulations.'));

		s = m.section(form.TypedSection, 'wifi-device', _('Radios'));
		s.anonymous = false;
		s.addremove = false;

		o = s.option(form.Value, 'country', _('Country code'), _('Two-letter ISO code, e.g. VN. Determines channels and the maximum tx power.'));
		o.placeholder = '00'; o.datatype = 'rangelength(2,2)'; o.rmempty = true;

		o = s.option(form.Value, 'txpower', _('Tx power (dBm)'), _('Empty = maximum allowed by the regulatory domain and the calibration data.'));
		o.datatype = 'range(1,30)'; o.rmempty = true; o.placeholder = _('max');

		o = s.option(form.ListValue, 'htmode', _('Channel width'), _('Narrower channels reach further and resist interference better.'));
		o.value('HE20', '20 MHz'); o.value('HE40', '40 MHz'); o.value('HE80', '80 MHz'); o.value('HE160', '160 MHz');

		o = s.option(form.ListValue, 'cell_density', _('Cell density'), _('Disabled keeps the lowest basic rates so far clients can still connect.'));
		o.value('0', _('Disabled')); o.value('1', _('Normal')); o.value('2', _('High')); o.value('3', _('Very high'));
		o.default = '0';

		o = s.option(form.Flag, 'he_su_beamformer', _('HE SU beamformer'));
		o.default = o.enabled;
		o = s.option(form.Flag, 'he_mu_beamformer', _('HE MU beamformer (MU-MIMO)'));
		o.default = o.enabled;
		o = s.option(form.Flag, 'mu_beamformer', _('VHT MU beamformer'));
		o.default = o.enabled;

		o = s.option(form.Value, 'distance', _('Coverage distance (m)'), _('Raise only for long outdoor links; adjusts ACK timeout.'));
		o.datatype = 'range(0,30000)'; o.rmempty = true;

		o = s.option(form.Flag, 'noscan', _('Force 40 MHz (no coexistence scan)'), _('2.4 GHz only. Ignores overlapping networks; may disturb neighbours.'));

		s = m.section(form.TypedSection, 'wifi-iface', _('Access points'));
		s.anonymous = true; s.addremove = false;
		s.filter = function(name) { return uci.get('wireless', name, 'mode') === 'ap'; };
		s.sectiontitle = function(name) { return (uci.get('wireless', name, 'ssid') || name) + ' (' + uci.get('wireless', name, 'device') + ')'; };

		o = s.option(form.Flag, 'disassoc_low_ack', _('Disconnect on low ACK'), _('Disable to keep weak clients (behind walls) connected.'));
		o.default = o.enabled;
		o = s.option(form.Flag, 'ieee80211k', _('802.11k neighbour reports'));
		o = s.option(form.Flag, 'bss_transition', _('802.11v BSS transition'));
		o = s.option(form.Flag, 'isolate', _('Client isolation'));

		return m.render().then(function(mapEl) {
			var presets = E('div', { 'class': 'cbi-section' }, [
				E('h3', _('Coverage presets')),
				E('p', _('"Through-wall": tx power at the legal maximum, 20 MHz on 2.4 GHz, low basic rates allowed, beamforming on, weak clients not kicked. "Balanced" restores the OpenWrt defaults for these options.')),
				E('button', { 'class': 'btn cbi-button-action', 'click': function() { return self.applyPreset('wall'); } }, _('Apply "Through-wall"')), ' ',
				E('button', { 'class': 'btn', 'click': function() { return self.applyPreset('default'); } }, _('Apply "Balanced"'))
			]);
			return E([], [ mapEl, presets, self.renderSlots(st) ]);
		});
	}
});
