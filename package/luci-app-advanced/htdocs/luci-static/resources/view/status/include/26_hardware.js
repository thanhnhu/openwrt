'use strict';
'require baseclass';
'require fs';

/* Extra rows on the LuCI Overview page: CPU temperature and NAND flash type. */

function fmtTemp(mc) {
	if (mc == null || isNaN(mc))
		return E('em', _('unknown'));

	var c = mc / 1000, color = c >= 85 ? '#d9534f' : c >= 70 ? '#f0ad4e' : null;
	return E('span', color ? { 'style': 'color:' + color + ';font-weight:bold' } : {},
		'%.1f °C'.format(c));
}

function fmtNand(n) {
	if (!n || !n.vendor)
		return E('em', _('unknown'));

	var s = n.vendor + ' SPI-NAND';
	if (n.size) s += ', ' + n.size;
	if (n.guess) s += ' (≈ ' + n.guess + ')';

	var d = [];
	if (n.oob) d.push('OOB ' + n.oob + ' B');
	if (n.ecc) d.push('ECC ' + n.ecc + ' bit/512 B');

	return E('span', { 'title': d.join(', ') }, s + (d.length ? ' — ' + d.join(', ') : ''));
}

return baseclass.extend({
	title: _('Hardware'),

	load: function() {
		return fs.exec('/usr/libexec/hwinfo', [ ]).then(function(r) {
			try { return JSON.parse(r.stdout); } catch (e) { return null; }
		}).catch(function() { return null; });
	},

	render: function(info) {
		if (!info)
			return E([]);

		return E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, _('CPU temperature')),
				E('td', { 'class': 'td left' }, fmtTemp(info.temp))
			]),
			E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, _('NAND flash')),
				E('td', { 'class': 'td left' }, fmtNand(info.nand))
			])
		]);
	}
});
