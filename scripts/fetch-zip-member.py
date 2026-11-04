#!/usr/bin/env python3
"""Extracts members of a remote zip with HTTP range requests, for archives
far larger than the files wanted from them.

usage: fetch-zip-member.py <url> <out-dir> <member>...
"""
import io
import os
import shutil
import sys
import urllib.request
import zipfile

USER_AGENT = "sugu-build"


class RemoteFile(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        self.position = 0
        request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=60) as response:
            self.size = int(response.headers["Content-Length"])

    def seekable(self):
        return True

    def readable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=0):
        self.position = {0: offset, 1: self.position + offset, 2: self.size + offset}[whence]
        return self.position

    def readinto(self, buffer):
        if self.position >= self.size or not len(buffer):
            return 0
        end = min(self.position + len(buffer), self.size) - 1
        headers = {"User-Agent": USER_AGENT, "Range": f"bytes={self.position}-{end}"}
        request = urllib.request.Request(self.url, headers=headers)
        with urllib.request.urlopen(request, timeout=300) as response:
            data = response.read()
        buffer[: len(data)] = data
        self.position += len(data)
        return len(data)


def main():
    url, out, *members = sys.argv[1:]
    archive = zipfile.ZipFile(io.BufferedReader(RemoteFile(url), buffer_size=1 << 22))
    os.makedirs(out, exist_ok=True)
    for member in members:
        with archive.open(member) as source, open(os.path.join(out, os.path.basename(member)), "wb") as target:
            shutil.copyfileobj(source, target, 1 << 22)


main()
