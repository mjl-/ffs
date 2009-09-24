implement Ffs;

include "sys.m";
	sys: Sys;
	sprint: import sys;
include "util0.m";
	util: Util0;
	warn, preadn, hex, l2a, rev, gbuf, g8, g16l, g32l, g32il, g64l: import util;
include "ffs.m";

dflag = 1;

fstypes = array[] of {
"unused", "swap", "v6", "v7",
"sysv", "v71k", "v8", "bsdffs",
"msdos", "bsdlfs", "other", "hpfs",
"iso9660", "boot", "ados", "hfs",
"adfs", "ext2fs", "ccd", "raid",
"ntfs", "udf",
};

init()
{
	sys = load Sys Sys->PATH;
	util = load Util0 Util0->PATH;
	util->init();
}

Disklabel.parse(buf: array of byte): (ref Disklabel, string)
{
	{
		d := ref Disklabel;
		o := 0;
		(d.magic, o) = g32il(buf, o);
		if(d.magic != Disklabelmagic)
			return (nil, "bad magic");
                (d.drvtype, o) = g16l(buf, o);
                (d.drvsubtype, o) = g16l(buf, o);
		(d.typename, o) = gstr(buf, o, 16);
                (d.packname, o) = gstr(buf, o, 16);
                (d.secsize, o)	= g32il(buf, o);
                (d.nsectors, o)	= g32il(buf, o);
                (d.ntracks, o) = g32il(buf, o);
                (d.ncyls, o) = g32il(buf, o);
                (d.secpercyl, o) = g32il(buf, o);
                (d.secperunit, o) = g32il(buf, o);
                (d.sparespertrack, o) = g16l(buf, o);
                (d.sparespercyl, o) = g16l(buf, o);
                (d.altcyls, o) = g32il(buf, o);
                (d.rpm, o) = g16l(buf, o);
                (d.interleave, o) = g16l(buf, o);
                (d.trackskew, o) = g16l(buf, o);
                (d.cylskew, o) = g16l(buf, o);
                (d.headswitch, o) = g32il(buf, o);
                (d.trkseek, o) = g32il(buf, o);
                (d.flags, o) = g32il(buf, o);
		d.drivedata = array[5] of int;
		for(i := 0; i < len d.drivedata; i++)
			(d.drivedata[i], o) = g32il(buf, o);
                (d.secperunith, o) = g16l(buf, o);
                (d.version, o) = g16l(buf, o);
		d.spare = array[4] of int;
		for(i = 0; i < len d.spare; i++)
			(d.spare[i], o)	= g32il(buf, o);
                (d.magic2, o) = g32il(buf, o);
		if(d.magic2 != Disklabelmagic)
			return (nil, "bad magic2");
                (d.checksum, o) = g16l(buf, o);
                (d.nparts, o) = g16l(buf, o);
                (d.bbsize, o) = g32il(buf, o);
                (d.sbsize, o) = g32il(buf, o);
		if(d.nparts > 32)
			return (nil, "too many partitions");
		d.parts = array[d.nparts] of {* => ref Dlpart};
		for(i = 0; i < d.nparts; i++) {
			p := d.parts[i];
			(p.nsectors, o) = g32l(buf, o);
			t: int;
			(p.firstsector, o) = g32l(buf, o);
			(t, o) = g16l(buf, o);
			p.firstsector |= big t<<32;
			(t, o) = g16l(buf ,o);
			p.nsectors |= big t<<32;
			(p.fstype, o) = g8(buf, o);
			(p.fragblock, o) = g8(buf, o);
			(p.ncylpergroup, o) = g16l(buf, o);
		}
		return (d, nil);

	} exception {
	"array bounds error" =>
		return (nil, "short buffer");
	}
}

Disklabel.read(fd: ref Sys->FD): (ref Disklabel, string)
{
	Disklabeloffset: con big 512;
	buf := array[Disklabellen] of byte;
	n := preadn(fd, buf, len buf, Disklabeloffset);
	if(n != len buf)
		return (nil, sprint("read disklabel: %r"));

	return Disklabel.parse(buf);
}

Disklabel.get(fd: ref Sys->FD, label: int): (ref Disklabel, ref Dlpart, big, string)
{
	(dl, err) := Disklabel.read(fd);
	if(err != nil)
		return (nil, nil, big 0, err);
	if(label < 0 || label >= len dl.parts)
		return (nil, nil, big 0, "no such label");
	p := dl.parts[label];
	if(p.fstype == FSunused)
		return (nil, nil, big 0, "label not in use");
	return (dl, p, p.firstsector*big 512, nil);
}


gcsum(buf: array of byte, o: int): (Csum, int)
{
	c: Csum;
	(c.ndir, o) = g32il(buf, o);
	(c.nfreeblocks, o) = g32il(buf, o);
	(c.nfreeinodes, o) = g32il(buf, o);
	(c.nfreefrags, o) = g32il(buf, o);
	return (c, o);
}

csumtext(c: Csum): string
{
	return sprint("Csum(ndir %d, nfreeblocks %d, nfreeinodes %d, nfreefrags %d)", c.ndir, c.nfreeblocks, c.nfreeinodes, c.nfreefrags);
}

gcsumtotal(buf: array of byte, o: int): (Csumtotal, int)
{
	c: Csumtotal;
	(c.ndir, o) = g64l(buf, o);
	(c.nfreeblocks, o) = g64l(buf, o);
	(c.nfreeinodes, o) = g64l(buf, o);
	(c.nfreefrags, o) = g64l(buf, o);
	(c.spare, o) = gbuf(buf, o, 4*8);
	return (c, o);
}

csumtotaltext(c: Csumtotal): string
{
	return sprint("Csumtotal(ndir %bd, nfreeblocks %bd, nfreeinodes %bd, nfreefrags %bd)", c.ndir, c.nfreeblocks, c.nfreeinodes, c.nfreefrags);
}

Super.read(fd: ref Sys->FD, off: big): (ref Super, string)
{
	buf := array[Superlen] of byte;
	n := preadn(fd, buf, len buf, off);
	if(n != len buf)
		return (nil, sprint("reading super: %r"));
	return Super.parse(buf);
}

Super.parse(buf: array of byte): (ref Super, string)
{
	ptrsize := 4;
	{
		s := ref Super;
		o := 0;
		(s.firstfield, o) = g32il(buf, o);
		(s.unused1, o) = g32il(buf, o);
		(s.superblock, o) = g32il(buf, o);
		(s.offcyl, o) = g32il(buf, o);
		(s.offinode, o) = g32il(buf, o);
		(s.offdata, o) = g32il(buf, o);
		(s.cgoffset, o) = g32il(buf, o);
		(s.cgmask, o) = g32il(buf, o);
		(s.ffs1time, o) = g32il(buf, o);
		(s.ffs1nblocks, o) = g32il(buf, o);
		(s.ffs1ndblocks, o) = g32il(buf, o);
		(s.ncylg, o) = g32il(buf, o);
		(s.blocksize, o) = g32il(buf, o);
		(s.fragsize, o) = g32il(buf, o);
		(s.nblockfrags, o) = g32il(buf, o);
		(s.minfree, o) = g32il(buf, o);
		(s.rotdelay, o) = g32il(buf, o);
		(s.rps, o) = g32il(buf, o);
		(s.bmask, o) = g32il(buf, o);
		(s.fmask, o) = g32il(buf, o);
		(s.bshift, o) = g32il(buf, o);
		(s.fshift, o) = g32il(buf, o);
		(s.maxcontig, o) = g32il(buf, o);
		(s.maxcylgblocks, o) = g32il(buf, o);
		(s.fragshift, o) = g32il(buf, o);
		(s.fsbtodbshift, o) = g32il(buf, o);
		(s.supersize, o) = g32il(buf, o);
		(s.csummask, o) = g32il(buf, o);
		(s.csumshift, o) = g32il(buf, o);
		(s.nindblocks, o) = g32il(buf, o);
		(s.nblockinodes, o) = g32il(buf, o);
		(s.nspf, o) = g32il(buf, o);
		(s.optim, o) = g32il(buf, o);
		(s.ntracksectors, o) = g32il(buf, o);
		(s.interleave, o) = g32il(buf, o);
		(s.trackskew, o) = g32il(buf, o);
		(s.id, o) = g64l(buf, o);
		(s.ffs1csumaddr, o) = g32il(buf, o);
		(s.csumsize, o) = g32il(buf, o);
		(s.cgbsize, o) = g32il(buf, o);
		(s.ncyltracks, o) = g32il(buf, o);
		(s.ntracksectors2, o) = g32il(buf, o);
		(s.ncylsectors, o) = g32il(buf, o);
		(s.ncyl, o) = g32il(buf, o);
		(s.ngroupcyls, o) = g32il(buf, o);
		(s.ngroupinodes, o) = g32il(buf, o);
		(s.nfraggrpblocks, o) = g32il(buf, o);
		(s.ffs1cylsum, o) = gcsum(buf, o);
		(s.supermodflag, o) = g8(buf, o);
		(s.clean, o) = g8(buf, o);
		(s.romntflag, o) = g8(buf, o);
		(s.ffs1flags, o) = g8(buf, o);
		(s.fsmnt, o) = gstr(buf, o, 468);
		(s.volname, o) = gstr(buf, o, 32);
		(s.uid, o) = g64l(buf, o);

                (s.pad, o) = g32il(buf, o);
                (s.cylgrotor, o) = g32il(buf, o);
                (s.ocsp, o) = gbuf(buf, o, ((128/ptrsize)-4)*ptrsize);
                (s.ptrs, o) = gbuf(buf, o, 4*ptrsize);
                (s.ncyclecyl, o) = g32il(buf, o);
                (s.maxbsize, o) = g32il(buf, o);
                (s.spareconf, o) = gbuf(buf, o, 17*8);
                (s.stdsuperoff, o) = g64l(buf, o);
                (s.cylsum, o) = gcsumtotal(buf, o);
                (s.lastwrite, o) = g64l(buf, o);
                (s.nblocks, o) = g64l(buf, o);
                (s.ndblocks, o) = g64l(buf, o);
                (s.cylgsumaddr, o) = g64l(buf, o);
                (s.npendingfreeblocks, o) = g64l(buf, o);
                (s.npendingfreeincodes, o) = g32il(buf, o);
                (s.snap, o) = gbuf(buf, o, 20*4);
                (s.expavgfilesize, o) = g32il(buf, o);
                (s.expavgdirfiles, o) = g32il(buf, o);
                (s.sparecon, o) = gbuf(buf, o, 26*4);
                (s.flags, o) = g32il(buf, o);
                (s.lastfscktime, o) = g32il(buf, o);
                (s.contigsumsize, o) = g32il(buf, o);
                (s.maxinlinesymlinklen, o) = g32il(buf, o);
                (s.inodefmt, o) = g32il(buf, o);
                (s.maxfilesize, o) = g64l(buf, o);
                (s.qbmask, o) = g64l(buf, o);
                (s.qfmask, o) = g64l(buf, o);
                (s.state, o) = g32il(buf, o);
                (s.postableformat, o) = g32il(buf ,o);
                (s.nrotpos, o) = g32il(buf, o);
                (s.postableoff, o) = g32il(buf, o);
                (s.nrotblocks, o) = g32il(buf, o);
                (s.magic, o) = g32il(buf, o);
                (s.space, o) = g8(buf, o);

		if(s.magic != Supermagic)
			return (nil, sprint("bad magic %#ux, perhaps fs was made on big-endian or 64-bit machine?", s.magic));

		return (s, nil);
	} exception {
	"array bounds error" =>
		return (nil, "short buffer");
	}
}

Super.text(s: self ref Super): string
{
	r := "Super:\n";
	r += sprint("	firstfield %d\n", s.firstfield);
	r += sprint("	unused1 %d\n", s.unused1);
	r += sprint("	superblock %d\n", s.superblock);
	r += sprint("	offcyl %d\n", s.offcyl);
	r += sprint("	offinode %d\n", s.offinode);
	r += sprint("	offdata %d\n", s.offdata);
	r += sprint("	cgoffset %d\n", s.cgoffset);
	r += sprint("	cgmask %#ux\n", s.cgmask);
	r += sprint("	ffs1time %d\n", s.ffs1time);
	r += sprint("	ffs1nblocks %d\n", s.ffs1nblocks);
	r += sprint("	ffs1ndblocks %d\n", s.ffs1ndblocks);
	r += sprint("	ncylg %d\n", s.ncylg);
	r += sprint("	blocksize %d\n", s.blocksize);
	r += sprint("	fragsize %d\n", s.fragsize);
	r += sprint("	nblockfrags %d\n", s.nblockfrags);
	r += sprint("	minfree %d\n", s.minfree);
	r += sprint("	rotdelay %d\n", s.rotdelay);
	r += sprint("	rps %d\n", s.rps);
	r += sprint("	bmask %#ux\n", s.bmask);
	r += sprint("	fmask %#ux\n", s.fmask);
	r += sprint("	bshift %d\n", s.bshift);
	r += sprint("	fshift %d\n", s.fshift);
	r += sprint("	maxcontig %d\n", s.maxcontig);
	r += sprint("	maxcylgblocks %d\n", s.maxcylgblocks);
	r += sprint("	fragshift %d\n", s.fragshift);
	r += sprint("	fsbtodbshift %d\n", s.fsbtodbshift);
	r += sprint("	supersize %d\n", s.supersize);
	r += sprint("	csummask %#ux\n", s.csummask);
	r += sprint("	csumshift %d\n", s.csumshift);
	r += sprint("	nindblocks %d\n", s.nindblocks);
	r += sprint("	nblockinodes %d\n", s.nblockinodes);
	r += sprint("	nspf %d\n", s.nspf);
	r += sprint("	optim %d\n", s.optim);
	r += sprint("	ntracksectors %d\n", s.ntracksectors);
	r += sprint("	interleave %d\n", s.interleave);
	r += sprint("	trackskew %d\n", s.trackskew);
	r += sprint("	id %#bux\n", s.id);
	r += sprint("	ffs1csumaddr %d\n", s.ffs1csumaddr);
	r += sprint("	csumsize %d\n", s.csumsize);
	r += sprint("	cgbsize %d\n", s.cgbsize);
	r += sprint("	ncyltracks %d\n", s.ncyltracks);
	r += sprint("	ntracksectors2 %d\n", s.ntracksectors2);
	r += sprint("	ncylsectors %d\n", s.ncylsectors);
	r += sprint("	ncyl %d\n", s.ncyl);
	r += sprint("	ngroupcyls %d\n", s.ngroupcyls);
	r += sprint("	ngroupinodes %d\n", s.ngroupinodes);
	r += sprint("	nfraggrpblocks %d\n", s.nfraggrpblocks);

	r += sprint("	ffs1cylsum %s\n", csumtext(s.ffs1cylsum));
	r += sprint("	supermodflag %#ux\n", s.supermodflag);
	r += sprint("	clean %#ux\n", s.clean);
	r += sprint("	romntflag %#ux\n", s.romntflag);
	r += sprint("	ffs1flags %#ux\n", s.ffs1flags);
	r += sprint("	fsmnt %q\n", s.fsmnt);
	r += sprint("	volname %q\n", s.volname);
	r += sprint("	uid %#bux\n", s.uid);

	r += sprint("	cylgrotor %d\n", s.cylgrotor);
	r += sprint("	ncyclecyl %d\n", s.ncyclecyl);
	r += sprint("	maxbsize %d\n", s.maxbsize);
	r += sprint("	stdsuperoff %bd\n", s.stdsuperoff);
	r += sprint("	cylsum %s\n", csumtotaltext(s.cylsum));
	r += sprint("	lastwrite %bd\n", s.lastwrite);
	r += sprint("	nblocks %bd\n", s.nblocks);
	r += sprint("	ndblocks %bd\n", s.ndblocks);
	r += sprint("	cylgsumaddr %bd\n", s.cylgsumaddr);
	r += sprint("	npendingfreeblocks %bd\n", s.npendingfreeblocks);
	r += sprint("	npendingfreeincodes %d\n", s.npendingfreeincodes);
	r += sprint("	expavgfilesize %d\n", s.expavgfilesize);
	r += sprint("	expavgdirfiles %d\n", s.expavgdirfiles);
	r += sprint("	flags %#ux\n", s.flags);
	r += sprint("	lastfscktime %d\n", s.lastfscktime);
	r += sprint("	contigsumsize %d\n", s.contigsumsize);
	r += sprint("	maxinlinesymlinklen %d\n", s.maxinlinesymlinklen);
	r += sprint("	inodefmt %#ux\n", s.inodefmt);

	r += sprint("	maxfilesize %#bux\n", s.maxfilesize);
	r += sprint("	qbmask %#bux\n", s.qbmask);
	r += sprint("	qfmask %#bux\n", s.qfmask);

	r += sprint("	state %d\n", s.state);
	r += sprint("	postableformat %d\n", s.postableformat);
	r += sprint("	nrotpos %d\n", s.nrotpos);
	r += sprint("	postableoff %d\n", s.postableoff);
	r += sprint("	nrotblocks %d\n", s.nrotblocks);
	r += sprint("	magic %#ux\n", s.magic);
	r += sprint("	space %d\n", s.space);

	return r;
}


Cg.read(fd: ref Sys->FD, size: int, off: big): (ref Cg, string)
{
	buf := array[size] of byte;
	n := preadn(fd, buf, len buf, off);
	if(n != len buf)
		return (nil, sprint("reading cg: %r"));
	return Cg.parse(buf);
}

Cg.parse(buf: array of byte): (ref Cg, string)
{
	{
		c := ref Cg;
		o := 0;
		(c.firstfield, o) = g32il(buf, o);
		(c.magic, o) = g32il(buf, o);
		if(c.magic != Cgmagic)
			return (nil, sprint("bad cg magic %#ux, expecting %#ux", c.magic, Cgmagic));
		(c.lastwrite, o) = g32il(buf, o);
		(c.index, o) = g32il(buf, o);
		(c.ncyl, o) = g16l(buf, o);
		(c.niblocks, o) = g16l(buf, o);
		(c.ndblocks, o) = g32il(buf, o);
		(c.cs, o) = gcsum(buf, o);
		(c.rotor, o) = g32il(buf, o);
		(c.frotor, o) = g32il(buf, o);
		(c.irotor, o) = g32il(buf, o);
		c.fragcounts = array[8] of int;
		for(i := 0; i < len c.fragcounts; i++)
			(c.fragcounts[i], o) = g32il(buf, o);
		(c.nblocks, o) = g32il(buf, o);
		(c.freeblockpos, o) = g32il(buf, o);
		(c.iusedoff, o) = g32il(buf, o);
		(c.ifreeoff, o) = g32il(buf, o);
		(c.nextfreeoff, o) = g32il(buf, o);
		(c.clustersumoff, o) = g32il(buf, o);
		(c.nclusters, o) = g32il(buf, o);
		(c.ffs2niblocks, o) = g32il(buf, o);
		(c.lastinitinode, o) = g32il(buf, o);
		c.spare0 = array[3] of int;
		for(i = 0; i < len c.spare0; i++)
			(c.spare0[i], o) = g32il(buf, o);
		(c.ffs2lastwrite, o) = g64l(buf, o);
		c.spare1 = array[3] of big;
		for(i = 0; i < len c.spare1; i++)
			(c.spare1[i], o) = g64l(buf, o);
		return (c, nil);
	} exception {
	"array bounds error" =>
		return (nil, "short buffer");
	}
}

Cg.text(c: self ref Cg): string
{
	s := "";
	s += "Cg:\n";
	s += sprint("	firstfield %d\n", c.firstfield);
	s += sprint("	magic %#ux\n", c.magic);
	s += sprint("	lastwrite %d\n", c.lastwrite);
	s += sprint("	index %d\n", c.index);
	s += sprint("	ncyl %d\n", c.ncyl);
	s += sprint("	niblocks %d\n", c.niblocks);
	s += sprint("	ndblocks %d\n", c.ndblocks);
	s += sprint("	cylsum %s\n", csumtext(c.cs));
	s += sprint("	rotor %d\n", c.rotor);
	s += sprint("	frotor %d\n", c.frotor);
	s += sprint("	irotor %d\n", c.irotor);
	s += sprint("	fragcounts");
	for(i := 0; i < len c.fragcounts; i++)
		s += sprint(" %d", c.fragcounts[i]);
	s += "\n";
	s += sprint("	nblocks %d\n", c.nblocks);
	s += sprint("	freeblockpos %d\n", c.freeblockpos);
	s += sprint("	iusedoff %d\n", c.iusedoff);
	s += sprint("	ifreeoff %d\n", c.ifreeoff);
	s += sprint("	nextfreeoff %d\n", c.nextfreeoff);
	s += sprint("	clustersumoff %d\n", c.clustersumoff);
	s += sprint("	nclusters %d\n", c.nclusters);
	s += sprint("	ffs2niblocks %d\n", c.ffs2niblocks);
	s += sprint("	lastinitinode %d\n", c.lastinitinode);
	s += sprint("	spare0");
	for(i = 0; i < len c.spare0; i++)
		s += sprint(" %d", c.spare0[i]);
	s += "\n";
	s += sprint("	ffs2lastwrite %bd\n", c.ffs2lastwrite);
	s += sprint("	spare1");
	for(i = 0; i < len c.spare1; i++)
		s += sprint(" %bd", c.spare1[i]);
	s += "\n";
	return s;
}


Inode.read(fd: ref Sys->FD, off: big, nil: ref Super): (ref Inode, string)
{
	buf := array[Inodelen] of byte;
	n := preadn(fd, buf, len buf, off);
	if(n != len buf)
		return (nil, sprint("reading inode: %r (%d,%d)", n, len buf));
	return Inode.parse(buf);
}

Inode.parse(buf: array of byte): (ref Inode, string)
{
	{
		o := 0;
		i := ref Inode;
		(i.mode, o) = g16l(buf, o);
		(i.nlink, o) = g16l(buf, o);
		(i.oldids0, o) = g16l(buf, o);
		(i.oldids1, o) = g16l(buf, o);
		(i.length, o) = g64l(buf, o);
		(i.atime, o) = g32il(buf, o);
		o += 4;
		(i.mtime, o) = g32il(buf, o);
		o += 4;
		(i.ctime, o) = g32il(buf, o);
		o += 4;
		i.blockbuf = array[(12+3)*4] of {* => byte 0};
		i.blockbuf[:] = buf[o:o+len i.blockbuf];
		i.blocks = array[12] of int;
		for(j := 0; j < len i.blocks; j++)
			(i.blocks[j], o) = g32il(buf, o);
		i.indblocks = array[3] of int;
		for(j = 0; j < len i.indblocks; j++)
			(i.indblocks[j], o) = g32il(buf, o);
		(i.flags, o) = g32il(buf, o);
		(i.nblocks, o) = g32il(buf, o);
		(i.gen, o) = g32il(buf, o);
		(i.uid, o) = g32il(buf, o);
		(i.gid, o) = g32il(buf, o);
		(i.spare0, o) = g32il(buf, o);
		(i.spare1, o) = g32il(buf, o);
		return (i, nil);
	} exception {
	"array bounds error" =>
		return (nil, "short buffer");
	}
}

Inode.text(i: self ref Inode): string
{
	s := "Inode\n";
	s += sprint("	mode %#uo, nlink %d, length %bd, atime %d mtime %d, ctime %d\n",
		i.mode, i.nlink, i.length, i.atime, i.mtime, i.ctime);
	s += sprint("	flags %#ux, nblocks %d, gen %#ux, uid %d, gen %d\n",
		i.flags, i.nblocks, i.gen, i.uid, i.gid);
	s += "	blocks";
	for(j := 0; j < len i.blocks; j++)
		s += sprint(" %d", i.blocks[j]);
	s += "\n";
	s += "	indirect blocks";
	for(j = 0; j < len i.indblocks; j++)
		s += sprint(" %d", i.indblocks[j]);
	s += "\n";
	return s;
}

Entry.parse(buf: array of byte, o: int): (ref Entry, int, string)
{
	d := ref Entry;
	origo := o;
	(d.inode, o) = g32il(buf, o);
	(d.length, o) = g16l(buf, o);
	if(d.length == 0)
		return (nil, o, sprint("invalid zero length entry"));
	(d.dtype, o) = g8(buf, o);
	namelen: int;
	(namelen, o) = g8(buf, o);
	if(namelen < 0 || namelen > Maxnamelen)
		return (nil, o, sprint("name too long (%d, max %d)", namelen, Maxnamelen));
	(d.name, o) = gstr(buf, o, namelen);
	return (d, origo+d.length, nil);
}

Entry.text(e: self ref Entry): string
{
	return sprint("Entry(inode %d, length %d, dtype %#ux, name %#q)", e.inode, e.length, e.dtype, e.name);
}


Part.init(fd: ref Sys->FD, off: big): (ref Part, string)
{
	soff := off+Superoff;
	(s, err) := Super.read(fd, soff);
	if(err != nil)
		return (nil, err);

	cgoff := off+big s.fragsize*big s.offcyl;
	cg: ref Cg;
	(cg, err) = Cg.read(fd, s.blocksize, cgoff);
	if(err != nil)
		return (nil, err);

	root: ref Inode;
	rootoff := off + big s.offinode*big s.fragsize + big (Rootinode*Inodelen);
	(root, err) = Inode.read(fd, rootoff, s);
	if(err != nil)
		return (nil, "reading root inode: "+err);

	p := ref Part (off, fd, s, cg, root, s.fragsize, s.fragsize);
	return (p, nil);
}

Part.getblock(p: self ref Part, i: ref Inode, buf: array of byte, bn: int): string
{
	if(getblock(p.fd, p.off, i, buf, bn, p.bsize) < 0)
		return sprint("%r");
	return nil;
}

Part.inodewalk(p: self ref Part, i: ref Inode, elem: string): (ref Inode, ref Entry, string)
{
	end := int ((i.length+big p.bsize-big 1)/big p.bsize);
	for(bn := 0; bn < end; bn++) {
		err := p.getblock(i, buf := array[p.bsize] of byte, bn);
		if(err != nil)
			return (nil, nil, err);
		if(big bn*big p.bsize+big len buf > i.length)
			buf = buf[:int(i.length-big bn*big p.bsize)];
		oo := 0;
		while(oo < len buf) {
			e: ref Entry;
			(e, oo, err) = Entry.parse(buf, oo);
			if(err != nil)
				return (nil, nil, err);
			if(elem == e.name) {
				n: ref Inode;
				(n, err) = p.inodeget(e.inode);
				return (n, e, err);
			}
		}
	}
	return (nil, nil, nil);
}

Part.inoderead(p: self ref Part, i: ref Inode, n: int, o: big): (array of byte, string)
{
	if((i.mode & FTmask) == FTlnk && i.length <= big p.s.maxinlinesymlinklen) {
		e := o+big n;
		if(e > i.length)
			e = i.length;
		if(o < big 0)
			o = big 0;
		return (i.blockbuf[int o:int e], nil);
	}

	case i.mode & FTmask {
	FTsock =>	return (nil, "file is a socket");
	FTblk =>	return (nil, "file is a block device");
	FTchr =>	return (nil, "file is a character device");
	FTfifo =>	return (nil, "file is a fifo");
	}

	# we stop on block boundary so next (sequential) read is block-aligned
	mask := ~big (p.bsize-1);
	s := o & mask;
	e := (o+big n) & mask;
	if(o == e)
		e = o+big n;
	if(e > i.length)
		e = i.length;
	size := int (e-s);
	if(size < p.bsize)
		size = p.bsize;
	buf := array[size] of byte;
	bufp := buf;
	end := int ((e+big p.bsize-big 1)/big p.bsize);
	for(c := int (s/big p.bsize); c < end; c++) {
		err := p.getblock(i, bufp, c);
		if(err != nil)
			return (nil, err);
		if(p.bsize <= len bufp)
			bufp = bufp[p.bsize:];
	}
	return (buf[int (o-s):int (e-s)], nil);
}

Part.inodeget(p: self ref Part, i: int): (ref Inode, string)
{
	g := i/p.s.ngroupinodes;
	o := big g * big p.s.nfraggrpblocks * big p.s.fragsize;
	o += big p.s.offinode*big p.s.fragsize;
	li := i % p.s.ngroupinodes;
	o += big (li*Inodelen);
	return Inode.read(p.fd, p.off+o, p.s);
}

Part.inodedir(nil: self ref Part, i: ref Inode): (ref Inodedir, string)
{
	return (ref Inodedir (i, big 0, nil, big 0, 0, nil), nil);
}

Part.dirpeek(p: self ref Part, id: ref Inodedir, o: big): (ref Sys->Dir, string)
{
	if(id.next != nil)
		return (id.next, nil);
	if(o != id.offset)
		return (nil, sprint("bad directory offset1, %bd != %bd", o, id.offset));

	err: string;
	for(;;) {
		if(id.buf != nil && id.bo >= len id.buf) {
			id.bo = 0;
			id.b++;
			id.buf = nil;
		}
		if(id.buf == nil) {
			if(id.b*big p.bsize >= id.i.length)
				break;
			id.buf = array[p.bsize] of byte;
			err = p.getblock(id.i, id.buf, int id.b);
			if(err == nil && id.b*big p.bsize+big p.bsize > id.i.length)
				id.buf = id.buf[:int(id.i.length-id.b*big p.bsize)];
		}

		e: ref Entry;
		n: ref Inode;
		nbo: int;
		(e, nbo, err) = Entry.parse(id.buf, id.bo);
		if(err == nil)
			id.bo = nbo;
		if(err == nil && (e.inode == 0 || e.name == "." || e.name == ".."))
			continue;
		if(err == nil)
			(n, err) = p.inodeget(e.inode);
		if(err == nil)
			id.next = ref inode2dir(e.name, e.inode, n);
		break;
	}
	return (id.next, err);
}

Part.dirnext(p: self ref Part, id: ref Inodedir, o: big): (ref Sys->Dir, string)
{
	if(id.next == nil)
		(dir, err) := p.dirpeek(id, o);
	else if(o != id.offset)
		err = sprint("bad directory offset, %bd != %bd", o, id.offset);

	if(err == nil) {
		dir = id.next;
		id.next = nil;
		id.offset = o;
	}
	return (dir, err);
}

inode2dir(name: string, i: int, n: ref Inode): Sys->Dir
{
	mode := n.mode & 8r777;
	qt := Sys->QTFILE;
	qid := Sys->Qid (big i, n.gen, qt);
	case n.mode & FTmask {
	FTdir =>
		mode |= Sys->DMDIR;
		qt = Sys->QTDIR;
	FTblk or
	FTchr =>
		qid.path |= big g16l(n.blockbuf, 0).t0<<48;
	FTlnk =>
		qid.path |= big ~0<<32;
	}
	return Sys->Dir (name, string n.uid, string n.gid, "", qid, mode, n.atime, n.mtime, n.length, 0, 0);
}


inodereadn(fd: ref Sys->FD, off: big, bsize: int, i: ref Inode, buf: array of byte, n: int, o: big): int
{
	bn := int (o/big bsize);
	h := 0;
	while(h+bsize <= n) {
		nn := getblock(fd, off, i, buf[h:], bn, bsize);
		if(nn < 0)
			return nn;
		h += nn;
		bn++;
	}
	if(h < n) {
		block := array[bsize] of byte;
		nn := getblock(fd, off, i, block, bn, bsize);
		if(nn < 0)
			return nn;
		need := n-h;
		buf[h:] = block[:need];
		h += need;
	}
	return h;
}

# always returns whole blocks
getblock(fd: ref Sys->FD, off: big, i: ref Inode, buf: array of byte, bn: int, bsize: int): int
{
	if(big bn*big bsize > i.length) {
		sys->werrstr("read past last block");
		return -1;
	}

	err: string;
	n0 := len i.blocks;
	nind := bsize/4;
	if(bn < n0) {
		err = readblock(fd, off, buf, bsize, i.blocks[bn]);
	} else if(bn < n0+nind) {
		bn -= n0;
		err = readblock(fd, off, buf, bsize, i.indblocks[0]);
		if(err == nil) err = readblock(fd, off, buf, bsize, g32il(buf, int bn*4).t0);
	} else if(bn < n0+nind+nind*nind) {
		bn -= n0+nind;
		err = readblock(fd, off, buf, bsize, i.indblocks[1]);
		if(err == nil) err = readblock(fd, off, buf, bsize, g32il(buf, int (bn / nind)*4).t0);
		if(err == nil) err = readblock(fd, off, buf, bsize, g32il(buf, int (bn % nind)*4).t0);
	} else if(bn < n0+nind+nind*nind+nind*nind*nind) {
		bn -= n0+nind+nind*nind;
		err = readblock(fd, off, buf, bsize, i.indblocks[2]);
		if(err == nil) err = readblock(fd, off, buf, bsize, g32il(buf, int (bn / (nind*nind))*4).t0);
		if(err == nil) err = readblock(fd, off, buf, bsize, g32il(buf, int ((bn % (nind*nind))/nind)*4).t0);
		if(err == nil) err = readblock(fd, off, buf, bsize, g32il(buf, int (bn % nind)*4).t0);
	} else
		err = "file too big";

	if(err != nil) {
		sys->werrstr(err);
		return -1;
	}
	return bsize;
}

readblock(fd: ref Sys->FD, off: big, buf: array of byte, bsize: int, bn: int): string
{
	if(bn == 0) {
		buf[:] = array[bsize] of {* => byte 0};
		return nil;
	}

	o := off+big bn*big bsize;
	n := preadn(fd, buf, bsize, o);
	if(n != bsize)
		return sprint("bad/short read: want %d, got %d, bn %d, %r", bsize, n, bn);
	return nil;
}

gstr(buf: array of byte, o: int, n: int): (string, int)
{
	for(e := o; e < o+n; e++)
		if(buf[e] == byte 0)
			break;
	return (string buf[o:e], o+n);
}
