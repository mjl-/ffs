implement Disklabelfs;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "draw.m";
include "arg.m";
include "string.m";
	str: String;
include "daytime.m";
	daytime: Daytime;
include "styx.m";
	styx: Styx;
	Tmsg, Rmsg: import styx;
include "styxservers.m";
	styxserver: Styxservers;
	Styxserver, Navigator: import styxserver;
	nametree: Nametree;
	Tree: import nametree;
include "util0.m";
	util: Util0;
	preadn, l2a, fail, warn, kill, killgrp, pid: import util;
include "../lib/ffs.m";
	ffs: Ffs;
	Disklabel, Dlpart: import ffs;

Disklabelfs: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};


dflag: int;

fd: ref Sys->FD;
srv: ref Styxserver;
time0: int;
parts: string;
disklabel: ref Disklabel;

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	str = load String String->PATH;
	styx = load Styx Styx->PATH;
	styx->init();
	styxserver = load Styxservers Styxservers->PATH;
	styxserver->init(styx);
	nametree = load Nametree Nametree->PATH;
	nametree->init();
	daytime = load Daytime Daytime->PATH;
	util = load Util0 Util0->PATH;
	util->init();
	ffs = load Ffs Ffs->PATH;
	ffs->init();

	sys->pctl(Sys->NEWPGRP, nil);

	arg->init(args);
	arg->setusage(arg->progname()+" [-d] part");
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	ffs->dflag = dflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 1)
		arg->usage();

	f := hd args;
	fd = sys->open(f, Sys->OREAD);
	if(fd == nil)
		fail(sprint("open: %r"));

	Disklabeloffset: con big 512;
	buf := array[ffs->Disklabellen] of byte;
	n := preadn(fd, buf, len buf, Disklabeloffset);
	if(n != len buf)
		fail(sprint("read disklabel: %r"));

	(dl, err) := Disklabel.parse(buf);
	if(err != nil)
		fail(sprint("disklabel: %r"));
	disklabel = dl;

	time0 = daytime->now();

	gen := big 1;
	(tree, navc) := nametree->start();
	tree.create(big 0, dir(big 0, ".", Sys->DMDIR|8r555, big 0));
	tree.create(big 0, dir(gen++, "ctl", 8r444, big 0));
	parts = "";
	for(i := 0; i < len dl.parts; i++) {
		p := dl.parts[i];
		if(p.fstype == ffs->FSunused)
			continue;
		fstype := "unknown";
		if(p.fstype >= 0 && p.fstype < len ffs->fstypes)
			fstype = ffs->fstypes[p.fstype];
		length := big 512*p.nsectors;
		tree.create(big 0, dir(gen++, sprint("%c", 'a'+i), 8r666, length));
		parts += sprint("%c %bd %q\n", 'a'+i, length, fstype);
	}

	nav := Navigator.new(navc);
	msgc: chan of ref Tmsg;
	(msgc, srv) = Styxserver.new(sys->fildes(0), nav, big 0);
	spawn styxsrv(msgc);
}

dir(path: big, name: string, mode: int, length: big): Sys->Dir
{
	d: Sys->Dir;
	d.name = name;
	d.uid = d.gid = "disklabel";
	d.qid = Sys->Qid (path, 0, 0);
	if(mode & Sys->DMDIR)
		d.qid.qtype = Sys->QTDIR;
	else
		d.qid.qtype = Sys->QTFILE;
	d.mode = mode;
	d.atime = d.mtime = time0;
	d.length = length;
	d.dtype = d.dev = 0;
	return d;
}

styxsrv(msgc: chan of ref Tmsg)
{
next:
	for(;;) {
		mm := <-msgc;
		if(mm == nil)
			break next;
		pick m := mm {
		Readerror =>
			warn("read error: "+m.error);
			break next;
		}
		dostyx(mm);
	}
	killgrp(pid());
}

dostyx(mm: ref Tmsg)
{
	pick m := mm {
	Read =>
		(f, err) := srv.canread(m);
		if(err != nil)
			return styxerror(m, err);
		if(f.path == big 1) {
			srv.reply(styxserver->readstr(m, parts));
		} else if(f.path > big 1) {
			if((m.offset & big (512-1)) != big 0)
				return styxerror(m, "offset must be multiple of sector size 512");
			if(m.count & (512-1))
				return styxerror(m, "count must be multiple of sector size 512");
			n := m.count;
			if(n > 8*1024)
				n = 8*1024;
			buf := array[n] of byte;
			p := disklabel.parts[int f.path-2];
			o := p.firstsector*big 512+m.offset;
			e := p.firstsector*big 512+p.nsectors*big 512;
			if(o+big n > e)
				n = int (e-o);
			warn(sprint("read, offset %bd, count %d;  o %bd", m.offset, m.count, o));
			n = preadn(fd, buf, len buf, o);
			srv.reply(ref Rmsg.Read (m.tag, buf[:n]));
		} else {
			srv.default(mm);
		}
	Wstat =>
		if(isnulldir(m.stat))
			if(sys->fwstat(fd, m.stat) == 0) {
				srv.reply(ref Rmsg.Wstat (m.tag));
				return;
			}
		srv.default(mm);
	* =>
		srv.default(mm);
	}
}

isnulldir(d: Sys->Dir): int
{
	nd := Sys->nulldir;
	return d.name == nd.name &&
		d.uid == nd.uid &&
		d.gid == nd.gid &&
		d.qid.path == nd.qid.path &&
		d.qid.vers == nd.qid.vers &&
		d.qid.qtype == nd.qid.qtype &&
		d.mode == nd.mode &&
		d.atime == nd.atime &&
		d.mtime == nd.mtime &&
		d.length == nd.length;
}

styxerror(m: ref Tmsg, err: string)
{
	srv.reply(ref Rmsg.Error (m.tag, err));
}

say(s: string)
{
	if(dflag)
		warn(s);
}
