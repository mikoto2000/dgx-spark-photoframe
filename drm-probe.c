#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

#include <xf86drm.h>
#include <xf86drmMode.h>

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "Usage: %s DRM_DEVICE\n", argv[0]);
        return 1;
    }

    const char *device = argv[1];
    int fd = open(device, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        perror(device);
        return 1;
    }

    int result = 1;
    drmModeRes *resources = drmModeGetResources(fd);
    if (!resources) {
        fprintf(stderr, "Cannot query KMS resources for %s: ", device);
        perror(NULL);
        goto close_device;
    }

    // A primary DRM node grants master to the first client when it is free.
    // GETCONNECTOR only performs a forced probe for the current DRM master.
    if (!drmIsMaster(fd)) {
        fprintf(stderr, "Cannot probe %s: DRM master is unavailable.\n", device);
        goto free_resources;
    }

    for (int i = 0; i < resources->count_connectors; ++i) {
        uint32_t id = resources->connectors[i];
        drmModeConnector *connector = drmModeGetConnector(fd, id);
        if (!connector) {
            fprintf(stderr, "Cannot probe DRM connector %u on %s: ", id, device);
            perror(NULL);
            goto free_resources;
        }
        drmModeFreeConnector(connector);
    }
    result = 0;

free_resources:
    drmModeFreeResources(resources);
close_device:
    close(fd);
    return result;
}
