'use strict'


angular.module('protocole_map', ['protocole_map_carre', 'protocole_map_point_fixe', 'protocole_map_routier'])
  .factory 'protocolesFactory', (ProtocoleMapCarre, ProtocoleMapRoutier, ProtocoleMapPointFixe) ->
    (site, protocoleAlgoSite, mapDiv, allowEdit = true, siteCallback = {}) ->
      if protocoleAlgoSite == 'ROUTIER'
        return new ProtocoleMapRoutier(site, mapDiv, allowEdit, siteCallback)
      else if protocoleAlgoSite == 'CARRE'
        return new ProtocoleMapCarre(site, mapDiv, allowEdit, siteCallback)
      else if protocoleAlgoSite == 'POINT_FIXE'
        return new ProtocoleMapPointFixe(site, mapDiv, allowEdit, siteCallback)
      else
        throw "Error : unknown protocole #{protocoleAlgoSite}"

  .factory 'ProtocoleMap', ($rootScope, Backend, GoogleMaps) ->
    class ProtocoleMap
      constructor: (@site, mapDiv, @allowEdit, @siteCallback) ->
        @_localites = []
        @_step = 0
        @_steps = []
        @_googleMaps = new GoogleMaps(mapDiv, @mapsCallback())
        # POINT_FIXE && PEDESTRE
        @_circleLimit = undefined
        @_newSelection = false
        @_grille = []
        # ROUTIER
        @_tracet = {}
        @_tracet.length = 0
        @_firstPoint = undefined
        @_lastPoint = undefined
        @_points = []
        @_segments = []
        @_padded_points = []

      mapValidated: ->
        return false

      selectGrilleStoc: ->
        @_step = 1
        @updateSite()

      validOrigin: (grille_stoc) ->
        cell = @createCell(grille_stoc.centre.coordinates[1],
                           grille_stoc.centre.coordinates[0])
        @validNumeroGrille(cell, grille_stoc.numero, grille_stoc._id)
        @removeOrigin()
        @updateSite()

      createOriginPoint: ->
        @_circleLimit = new google.maps.Circle(
          map: @_googleMaps.getMap()
          center: @_googleMaps.getCenter()
          radius: 10000
          draggable: true
        )

      removeOrigin: ->
        @_newSelection = true
        @_circleLimit.setMap(null)
        @_circleLimit.setDraggable(false)

      deleteValidCell: ->
        @_grille[0].item.setMap(null)
        @_grille = []

      getOrigin: ->
        return @_circleLimit

      allowMapChanged: ->
        if not @site.verrouille?
          return true
        return false

      allowOverlayCreated: ->
        if not @site.verrouille?
          return true
        return false

      updateSite: ->
        steps =
          steps: @getSteps()
          step: @_step
          loading: @loading
        if @siteCallback.updateSteps?
          @siteCallback.updateSteps(steps)
        if not @loading and @siteCallback.updateForm?
          @siteCallback.updateForm()

      saveMap: ->
        result = []
        for localite in @_localites
          localiteToSave = {}
          shapetosave = {}
          shapetosave.type = localite.overlay.type
          if shapetosave.type == "Point"
            shapetosave.coordinates = @_googleMaps.getPosition(localite.overlay)
          else if shapetosave.type == "Polygon"
            shapetosave.coordinates = [ @_googleMaps.getPath(localite.overlay) ]
          else if shapetosave.type == "LineString"
            shapetosave.coordinates = @_googleMaps.getPath(localite.overlay)
          else
            continue
          localiteToSave =
            name: localite.name
            geometries:
              type: 'GeometryCollection'
              geometries: [shapetosave]
            representatif: false
          result.push(localiteToSave)
        return result

      mapsCallback: ->
        overlayCreated: -> false
        saveOverlay: -> false
        zoomChanged: -> false
        mapsMoved: -> false

      setLocaliteName: ->
        return ''

      loadMap: ->
        # start loading
        @loading = true
        # generate grille_stoc
        if @site.grille_stoc?
          @_step = 2
          @_googleMaps.setCenter(
            @site.grille_stoc.centre.coordinates[1],
            @site.grille_stoc.centre.coordinates[0]
          )
          @_googleMaps.setZoom(14)
          newCell = @createCell(
            @site.grille_stoc.centre.coordinates[1],
            @site.grille_stoc.centre.coordinates[0]
          )
          @validNumeroGrille(newCell, @site.grille_stoc.numero, @site.grille_stoc._id)
        # load localites
        for localite in @site.localites or []
          newLocalite =
            name: localite.nom
            representatif: localite.representatif
          newLocalite.overlay = @loadGeoJson(localite.geometries)
          @_localites.push(newLocalite)
        # end loading
        @loading = false

      loadGeoJson: (geoJson, callback=@mapsCallback.overlayCreated) ->
        overlay = undefined
        if not geoJson
          return
        if geoJson.type == 'GeometryCollection'
          for geometry in geoJson.geometries
            return @loadGeoJson(geometry)
        if geoJson.type == 'Point'
          overlay = @_googleMaps.createPoint(geoJson.coordinates[0],
                                            geoJson.coordinates[1],
                                            true)
        else if geoJson.type == 'Polygon'
          overlay = @_googleMaps.createPolygon(geoJson.coordinates[0], true, true)
        else if geoJson.type == 'LineString'
          overlay = @_googleMaps.createLineString(geoJson.coordinates, true, true)
        else
          throw "Error: Bad GeoJSON object #{geoJson}"
        overlay.type = geoJson.type
        if !@mapsCallback().overlayCreated(overlay)
          @_googleMaps.deleteOverlay(overlay)
        return overlay

      getIdGrilleStoc: ->
        return @_grille[0].id

      mapsChanged: ->
        if @_step != 1
          return
        zoomLevel = @_googleMaps.getZoom()
        bounds = @_googleMaps.getBounds()
        if not bounds?
          return
        southWest = bounds.getSouthWest()
        northEast = bounds.getNorthEast()
        if zoomLevel > 11
          parameters =
            sw_lat: southWest.lat()
            sw_lng: southWest.lng()
            ne_lat: northEast.lat()
            ne_lng: northEast.lng()
          Backend.all('grille_stoc/rectangle').getList(parameters)
            .then (@createGrille)

      createGrille: (grille_stoc) =>
        validNumeroGrille = (cell) =>
          (event) => @validNumeroGrille(cell)
        grille_stoc = grille_stoc.plain()
        for cell in grille_stoc
          exist = false
          for item in @_grille
            if item.numero == cell.numero
              exist = true
              break
          if exist
            continue
          newCell = @createCell(cell.centre.coordinates[1], cell.centre.coordinates[0])
          @_googleMaps.addListener(newCell, 'click', validNumeroGrille(newCell))
          @_grille.push({"item": newCell, "numero": cell.numero, 'id': cell._id})

      createCell: (lat, lng) ->
        # 1000*racine(2)
        distance = 1000 * Math.sqrt(2)
        origine = new google.maps.LatLng(lat, lng)
        southWest = google.maps.geometry.spherical.computeOffset(origine, distance, -135)
        northEast = google.maps.geometry.spherical.computeOffset(origine, distance, 45)
        item = new google.maps.Polygon(
          paths: [
            new google.maps.LatLng(southWest.lat(), northEast.lng())
            new google.maps.LatLng(northEast.lat(), northEast.lng())
            new google.maps.LatLng(northEast.lat(), southWest.lng())
            new google.maps.LatLng(southWest.lat(), southWest.lng())
          ]
          map: @_googleMaps.getMap()
          fillOpacity: 0
          strokeColor: '#606060'
          strokeOpacity: 0.65
          strokeWeight: 0.5
        )
        return item

      validNumeroGrille: (cell, numero, id) =>
        nbStoc = @_grille.length
        if nbStoc
          for index in [nbStoc-1..0]
            if @_grille[index].item != cell
              @_grille[index].item.setMap(null)
              @_grille.splice(index, 1)
        else
          @_grille.push({"item": cell, "numero": numero, "id": id})
        @_grille[0].item.setOptions(
          strokeColor: '#00E000'
          strokeOpacity: 1
          strokeWeight: 2
        )
        @_step = 2
        @updateSite()
        if @allowEdit
          @_googleMaps.addListener(@_grille[0].item, 'rightclick', (event) =>
            if confirm("Etes vous sûre de vouloir supprimer ce carré ainsi que toutes les localités qu'il contient ?")
              @_step = 0
              @_grille[0].item.setMap(null)
              @_grille = []
              @_googleMaps.emptyMap()
              @updateSite()
              @mapsChanged()
          )
          @_googleMaps.setDrawingManagerOptions(drawingControl: true)

      checkLength: (overlay) ->
        length = @_googleMaps.computeLength(overlay)
        if length < 1800
          overlay.setOptions(strokeColor: '#800090')
        else if length > 2200
          overlay.setOptions(strokeColor: '#FF0000')
        else
          overlay.setOptions(strokeColor: '#000000')
        return length

      checkTotalLength: ->
        if !@_tracet.overlay?
          return 0
        overlay = @_tracet.overlay
        length = @_googleMaps.computeLength(overlay)
        if length < 30000
          overlay.setOptions(strokeColor: '#FF0000')
        else
          overlay.setOptions(strokeColor: '#000000')
        return length

      getSteps: ->
        return @_steps

      emptyMap: ->
        for localite in @_localites
          localite.overlay.setMap(null)
        @_localites = []

      deleteOverlay: (overlay) ->
        for localite, key in @_localites
          if localite.overlay == overlay
            @_googleMaps.deleteOverlay(localite.overlay)
            @_localites.splice(key, 1);
            return

      getCountOverlays: (type = '') ->
        if type == ''
          return @_localites.length
        else
          result = 0
          for localite in @_localites or []
            if localite.overlay.type == type
              result++
          return result

      getTotalLength: ->
        result = 0
        for localite in @_localites
          if localite.overlay.type == 'LineString'
            result += @_googleMaps.computeLength(localite.overlay)
        return result

      getTracetLength: ->
        return @_tracet.length

      validTracet: ->
        if !@_tracet.overlay?
          return false
        # Fix tracet
        @_googleMaps.clearListeners(@_tracet.overlay, 'rightclick')
        @_tracet.overlay.setOptions(
          draggable: false
          editable: false
        )
        @_step = 1
        @updateSite()
        # Create origin points choice
        path = @_tracet.overlay.getPath()
        nbPoint = path.length
        firstPoint = path.getAt(0)
        lastPoint = path.getAt(nbPoint-1)
        @_firstPoint = @_googleMaps.createPoint(firstPoint.lat(), firstPoint.lng())
        @_lastPoint = @_googleMaps.createPoint(lastPoint.lat(), lastPoint.lng())
        @_googleMaps.addListener(@_firstPoint, 'click', @validOriginPoint)
        @_googleMaps.addListener(@_lastPoint, 'click', @validOriginPoint)
        # Pad the points array
        interval = 10
        for key in [0..path.getLength()-1]
          current_point = path.getAt(key)
          next_point = path.getAt(key+1)
          # Check if we're on the last point
          if (typeof next_point != 'undefined')
            distance = @_googleMaps.computeDistanceBetween(current_point, next_point)
            nbSections = Math.floor(distance/interval)+1
            # Get a 10th of the difference in latitude
            lat_incr = (next_point.lat() - current_point.lat()) / nbSections
            # Get a 10th of the difference in longitude
            lng_incr = (next_point.lng() - current_point.lng()) / nbSections
            # Now add interval points at lat_incr & lng_incr intervals between current and next points
            # We add this to the new padded_points array
            for i in [0..nbSections-1]
              new_pt = new google.maps.LatLng(current_point.lat() + (i * lat_incr), current_point.lng() + (i * lng_incr))
              if !(key == 0 && i == 0)
                if @_googleMaps.isLocationOnEdge(new_pt, [current_point, next_point])
                  @_padded_points.push(new_pt)
                else
                  console.log("Error : some points not on path")
        return true

      # Used for ROUTIER protocole
      validOriginPoint: (e) =>
        # Up to date step
        @_step = 2
        # If click on first point
        if e.latLng.lat() == @_firstPoint.getPosition().lat() &&
           e.latLng.lng() == @_firstPoint.getPosition().lng()
          @_points.push(@_firstPoint)
          @_points.push(@_lastPoint)
        # If click on last point
        else
          @_points.push(@_lastPoint)
          @_points.push(@_firstPoint)
          path = @_tracet.overlay.getPath()
          new_path = []
          for i in [0..path.getLength()-1]
            new_path.push(path.pop())
          @_tracet.overlay.setPath(new_path)
        # Set titles and edge
        @_points[0].setTitle("Départ")
        @_points[1].setTitle("Arrivée")
        @_points[0].edge = 0
        @_points[1].edge = @_tracet.overlay.getPath().getLength()-2
        # Events
        @_googleMaps.addListener(@_tracet.overlay, 'click', @addSegmentPoint)
        @_googleMaps.clearListeners(@_firstPoint, 'click')
        @_googleMaps.clearListeners(@_lastPoint, 'click')
        # Others
        @updateSite()

      addSegmentPoint: (e) =>
        closestPoint = @_googleMaps.findClosestPointOnPath(e.latLng, @_padded_points)
        point = @_googleMaps.createPoint(closestPoint.lat(), closestPoint.lng())
        @_googleMaps.addListener(point, 'rightclick', (e) =>
          @deletePoint(point)
        )
        point.setOptions({draggable: true})
        @_googleMaps.addListener(point, 'dragend', (e) =>
          point.setPosition(@_googleMaps
            .findClosestPointOnPath(e.latLng, @_padded_points))
          @updatePointPosition(point)
          @generateSegments()
        )
        @_googleMaps.addListener(point, 'drag', (e) =>
          point.setPosition(@_googleMaps
            .findClosestPointOnPath(e.latLng, @_padded_points))
        )
        # find vertex of new point
        path = @_tracet.overlay.getPath()
        nbPoints = path.getLength()
        index = undefined
        vertex = []
        for key in [0..nbPoints-2]
          currVertex = [path.getAt(key), path.getAt(key+1)]
          vertex.push(currVertex)
          if @_googleMaps.isLocationOnEdge(point.getPosition(), currVertex)
            index = key
            point.edge = key
        if !index?
          @_googleMaps.deleteOverlay(point)
          throw "Error : Can not find Edge of new point"
        stop = false
        for pt, key in @_points
          for currVertex, keyVertex in vertex
            if @_googleMaps.isLocationOnEdge(pt.getPosition(), currVertex)
              if keyVertex < index
                break
              else if keyVertex > index
                stop = true
                @_points.splice(key, 0, point)
                break
              else
                d1 = @_googleMaps.computeDistanceBetween(currVertex[0], point.getPosition())
                d2 = @_googleMaps.computeDistanceBetween(currVertex[0], pt.getPosition())
                if d1 < d2
                  stop = true
                  @_points.splice(key, 0, point)
                  break
                else
                  break
            else
              continue
          if stop
            break
        @generateSegments()

      deletePoint: (overlay) ->
        for point, key in @_points
          if point == overlay
            @_googleMaps.deleteOverlay(point)
            @_points.splice(key, 1)
            @generateSegments()
            return

      generateSegments: ->
        colors = [
          '#FF8000'
          '#FFFF00'
          '#80FF00'
          '#00FF00'
          '#00FF80'
          '#00FFFF'
          '#0080FF'
          '#0000FF'
          '#8000FF'
          '#FF00FF'
          '#FF0080'
        ]
        for segment in @_segments
          @_googleMaps.deleteOverlay(segment)
        @_segments = []
        nbPoints = @_points.length
        key = 0
        while (key < nbPoints-1)
          segment = @generateSegment(key)
          segment.setOptions({ strokeColor: colors[(key/2)%11], zIndex: 10 })
          @_googleMaps.addListener(segment, 'click', @addSegmentPoint)
          @_segments.push(segment)
          key +=2

      # generate the segment between @_points[key] and @_points[key+1] points
      generateSegment: (key) ->
        tracet = @_tracet.overlay.getPath()
        path = []
        start = @_points[key]
        stop = @_points[key+1]
        path.push([start.getPosition().lat(), start.getPosition().lng()])
        if start.edge < stop.edge
          for corner in [start.edge+1..stop.edge]
            pt = tracet.getAt(corner)
            path.push([pt.lat(), pt.lng()])
        path.push([stop.getPosition().lat(), stop.getPosition().lng()])
        return @_googleMaps.createLineString(path)

      updatePointPosition: (point) ->
        path = @_tracet.overlay.getPath()
        for key in [0..path.getLength()-2]
          vertex = [path.getAt(key), path.getAt(key+1)]
          if @_googleMaps.isLocationOnEdge(point.getPosition(), vertex)
            point.edge = key

      validSegments: ->
        colors = [
          '#FF8000'
          '#80FF00'
          '#00FF80'
          '#0080FF'
          '#FF0080'
        ]
        # Events
        @_googleMaps.clearListeners(@_tracet.overlay, 'click')
        for segment in @_segments or []
          @_googleMaps.clearListeners(segment, 'click')
        for point in @_points or []
          @_googleMaps.clearListeners(point, 'drag')
          @_googleMaps.clearListeners(point, 'dragend')
          point.setMap(null)
        # generation of sites
        locBySegment = 5
        localites = []
        for segment, key in @_segments or []
          delta = @_googleMaps.computeLength(segment) / locBySegment
          path = segment.getPath()
          # For each site
          for secteur in [1..5]
            localite = {}
            localite.name = 'T '+(key+1)+' '+secteur
            currLength = 0
            secteurPath = [segment.getPath().getAt(0)]
            end = false
            while path.getLength() > 1 && !end
              d = @_googleMaps.computeDistanceBetween(path.getAt(0), path.getAt(1))
              if (d + currLength < delta) && (secteur < 5)
                console.log(localite.name+": Longeur du segment trop petit")
                currLength += d
                secteurPath.push(path.getAt(1))
                path.removeAt(0)
              else
                console.log(localite.name+": On va pouvoir finir")
                end = true
                # Compute where is the cut point
                rest = delta - currLength
                ratio = d / rest
                lat_incr = (path.getAt(1).lat() - path.getAt(0).lat()) / ratio
                lng_incr = (path.getAt(1).lng() - path.getAt(0).lng()) / ratio
                cut_point = new google.maps.LatLng(path.getAt(0).lat() + lat_incr, path.getAt(0).lng() + lng_incr)
                # finish secteur and cut segment
                secteurPath.push(cut_point)
                path.setAt(0, cut_point)
            secteurLineString = @_googleMaps.createLineStringWithPath(secteurPath)
            secteurLineString.setOptions({'strokeColor': colors[secteur]})
            secteurLineString.setOptions({'zIndex': 20})
            localite.overlay = secteurLineString
            localite.overlay.type = 'LineString'
            localite.representatif = false
            @_localites.push(localite)
        @_step = 4
        @updateSite()
        return true
