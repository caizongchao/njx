#include <windows.h>
#include <stdio.h>

#define flags2 (FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED)

int main() {
    auto fASync = false;

    constexpr size_t flags1 = FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE;
    

    auto hDir = CreateFile(
        "DirName",
        FILE_LIST_DIRECTORY,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL,
        OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS | (fASync ? FILE_FLAG_OVERLAPPED : 0),
        NULL);

    return 0;
}