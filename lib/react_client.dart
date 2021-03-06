// Copyright (c) 2013, the Clean project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library react_client;

import "package:react/react.dart";
import "dart:js";
import "dart:html";
import "dart:async";

var _React = context['React'];
var _Object = context['Object'];

const PROPS = 'props';
const INTERNAL = '__internal__';
const COMPONENT = 'component';
const IS_MOUNTED = 'isMounted';
const REFS = 'refs';

newJsObjectEmpty() {
  return new JsObject(_Object);
}

final emptyJsMap = newJsObjectEmpty();
newJsMap(Map map) {
  var JsMap = newJsObjectEmpty();
  for (var key in map.keys) {
    if(map[key] is Map) {
      JsMap[key] = newJsMap(map[key]);
    } else {
      JsMap[key] = map[key];
    }
  }
  return JsMap;
}

/**
 * Type of [children] must be child or list of childs, when child is JsObject or String
 */
typedef JsObject ReactComponentFactory(Map props, [dynamic children]);
typedef Component ComponentFactory();


/** TODO Think about using Expandos */
_getInternal(JsObject jsThis) => jsThis[PROPS][INTERNAL];
_getProps(JsObject jsThis) => _getInternal(jsThis)[PROPS];
_getComponent(JsObject jsThis) => _getInternal(jsThis)[COMPONENT];
_getInternalProps(JsObject jsProps) => jsProps[INTERNAL][PROPS];

/**
 * wrapper for getDefaultProps.
 * Get internal, create component and place it to internal.
 *
 * Next get default props by component method and merge component.props into it
 * to update it with passed props from parent.
 *
 * @return jsProsp with internal with component.props and component
 */
_getDefaultProps(zone) => new JsFunction.withThis((jsThis) => zone.run(() {
  return newJsObjectEmpty();
}));


getRef(name, JsObject jsThis) {
  var ref = jsThis['refs'][name] as JsObject;
  if (ref[PROPS][INTERNAL] != null) return ref[PROPS][INTERNAL][COMPONENT];
  else return ref.callMethod('getDOMNode', []);
}

getDOMNode(jsThis) {
  return jsThis.callMethod("getDOMNode");
}

/**
 * get initial state from component.getInitialState, put them to state.
 *
 * @return empty JsObject as default state for javascript react component
 */
_getInitialState(zone, componentFactory) => new JsFunction.withThis((jsThis) => zone.run(() {

    var internal = _getInternal(jsThis);
    var redraw = () {
      if (internal[IS_MOUNTED]) {
        jsThis.callMethod('setState', [emptyJsMap]);
      }
    };


    Component component = componentFactory()
        ..initComponentInternal(internal[PROPS], redraw, getRef, getDOMNode);

    internal[COMPONENT] = component;
    internal[IS_MOUNTED] = false;
    internal[PROPS] = component.props;

    _getComponent(jsThis).initStateInternal();
    return newJsObjectEmpty();
  }));

_componentWillMount(zone) => new JsFunction.withThis((jsThis) => zone.run(() {
  _getInternal(jsThis)[IS_MOUNTED] = true;
  _getComponent(jsThis)
      ..componentWillMount()
      ..transferComponentState();
}));

_componentDidMount(zone) => new JsFunction.withThis((JsObject jsThis) => zone.run(() {
  //you need to get dom node by calling getDOMNode
  var rootNode = jsThis.callMethod("getDOMNode");
  _getComponent(jsThis).componentDidMount(rootNode);
}));

_getNextProps(Component component, newArgs) {
  var newProps = _getInternalProps(newArgs);
  return {}
    ..addAll(component.getDefaultProps())
    ..addAll(newProps != null ? newProps : {});
}

_afterPropsChange(Component component, newArgs) {
  /** add component to newArgs to keep component in internal */
  newArgs[INTERNAL][COMPONENT] = component;

  /** update component.props */
  component.props = _getNextProps(component, newArgs);

  /** update component.state */
  component.transferComponentState();
}

_componentWillReceiveProps(zone) => new JsFunction.withThis((jsThis, newArgs, [reactInternal]) => zone.run(() {
  var component = _getComponent(jsThis);
  component.componentWillReceiveProps(_getNextProps(component, newArgs));
}));

/**
 * count nextProps from jsNextProps, get result from component,
 * and if shoudln't update, update props and transfer state.
 */
_shouldComponentUpdate(zone) => new JsFunction.withThis((jsThis, newArgs, nextState, nextContext) => zone.run(() {
  Component component  = _getComponent(jsThis);
  /** use component.nextState where are stored nextState */
  if (component.shouldComponentUpdate(_getNextProps(component, newArgs),
                                      component.nextState)) {
    return true;
  } else {
    /**
     * if component shouldnt update, update props and tranfer state,
     * becasue willUpdate will not be called and so it will not do it.
     */
    _afterPropsChange(component, newArgs);
    return false;
  }
}));

/**
 * wrap component.componentWillUpdate and after that update props and transfer state
 */
_componentWillUpdate(zone) => 
    new JsFunction.withThis((jsThis, newArgs, nextState, [reactInternal]) => zone.run(() {
  Component component  = _getComponent(jsThis);
  component.componentWillUpdate(_getNextProps(component, newArgs),
                                component.nextState);
  _afterPropsChange(component, newArgs);
}));

/**
 * wrap componentDidUpdate and use component.prevState which was trasnfered from state in componentWillUpdate.
 */
_componentDidUpdate(zone) => new JsFunction.withThis((JsObject jsThis, prevProps, prevState, prevContext) => zone.run(() {
  var prevInternalProps = _getInternalProps(prevProps);
  //you don't get root node as parameter but need to get it directly
  var rootNode = jsThis.callMethod("getDOMNode");
  Component component = _getComponent(jsThis);
  component.componentDidUpdate(prevInternalProps, component.prevState, rootNode);
}));

_componentWillUnmount(zone) => new JsFunction.withThis((jsThis, [reactInternal]) => zone.run(() {
  _getInternal(jsThis)[IS_MOUNTED] = false;
  _getComponent(jsThis).componentWillUnmount();
}));

_renderComponent(zone) =>  new JsFunction.withThis((jsThis) => zone.run(() {
  return _getComponent(jsThis).render();
}));

ReactComponentFactory _registerComponent(ComponentFactory componentFactory, [Iterable<String> skipMethods = const []]) {

  var zone = Zone.current;
  
  // wrap component functions
  var getDefaultProps = _getDefaultProps(zone);
  var getInitialState = _getInitialState(zone, componentFactory);
  var componentWillMount = _componentWillMount(zone);
  var componentDidMount = _componentDidMount(zone);
  var componentWillReceiveProps = _componentWillReceiveProps(zone);
  var shouldComponentUpdate = _shouldComponentUpdate(zone);
  var componentWillUpdate = _componentWillUpdate(zone);
  var componentDidUpdate = _componentDidUpdate(zone);
  var componentWillUnmount = _componentWillUnmount(zone);
  var render = _renderComponent(zone);

  var skipableMethods = ['componentDidMount', 'componentWillReceiveProps',
                         'shouldComponentUpdate', 'componentDidUpdate',
                         'componentWillUnmount'];

  removeUnusedMethods(Map originalMap, Iterable removeMethods) {
    removeMethods.where((m) => skipableMethods.contains(m)).forEach((m) => originalMap.remove(m));
    return originalMap;
  }

  /**
   * create reactComponent with wrapped functions
   */
  var reactComponentFactory = _React.callMethod('createFactory', [
    _React.callMethod('createClass', [newJsMap(
      removeUnusedMethods({
        'componentWillMount': componentWillMount,
        'componentDidMount': componentDidMount,
        'componentWillReceiveProps': componentWillReceiveProps,
        'shouldComponentUpdate': shouldComponentUpdate,
        'componentWillUpdate': componentWillUpdate,
        'componentDidUpdate': componentDidUpdate,
        'componentWillUnmount': componentWillUnmount,
        'getDefaultProps': getDefaultProps,
        'getInitialState': getInitialState,
        'render': render
      }, skipMethods)
    )])
  ]);
  
  /**
   * return ReactComponentFactory which produce react component with set props and children[s]
   */
  return (Map props, [dynamic children]) {
    if (children == null) {
      children = [];
    } else if (children is! Iterable) {
      children = [children];
    }
    var extendedProps = new Map.from(props);
    extendedProps['children'] = children;

    var convertedArgs = newJsObjectEmpty();

    /**
     * add key to args which will be passed to javascript react component
     */
    if (extendedProps.containsKey('key')) {
      convertedArgs['key'] = extendedProps['key'];
    }

    if (extendedProps.containsKey('ref')) {
      convertedArgs['ref'] = extendedProps['ref'];
    }

    /**
     * put props to internal part of args
     */
    convertedArgs[INTERNAL] = {PROPS: extendedProps};

    return reactComponentFactory.apply([convertedArgs, new JsArray.from(children)]);
  };

}

/**
 * create dart-react registered component for html tag.
 */
_reactDom(String name) {
  return (Map args, [children]) {
    _convertBoundValues(args);
    _convertEventHandlers(args);
    if (args.containsKey('style')) {
      args['style'] = new JsObject.jsify(args['style']);
    }
    if (children is Iterable) {
      children = new JsArray.from(children);
    }
    return _React['createElement'].apply([name, newJsMap(args), children]);
  };
}

/**
 * Recognize if type of input (or other element) is checkbox by it's props.
 */
_isCheckbox(props) {
  return props['type'] == 'checkbox';
}

/**
 * get value from DOM element.
 *
 * If element is checkbox, return bool, else return value of "value" attribute
 */
_getValueFromDom(domElem) {
  var props = domElem.attributes;
  if (_isCheckbox(props)) {
    return domElem.checked;
  } else {
    return domElem.value;
  }
}

/**
 * set value to props based on type of input.
 *
 * Specialy, it recognized chceckbox.
 */
_setValueToProps(Map props, val) {
  if (_isCheckbox(props)) {
    if(val) {
      props['checked'] = true;
    } else {
      if(props.containsKey('checked')) {
         props.remove('checked');
      }
    }
  } else {
    props['value'] = val;
  }
}

/**
 * convert bound values to pure value
 * and packed onchanged function
 */
_convertBoundValues(Map args) {
  var boundValue = args['value'];
  if (args['value'] is List) {
    _setValueToProps(args, boundValue[0]);
    args['value'] = boundValue[0];
    var onChange = args["onChange"];
    /**
     * put new function into onChange event hanlder.
     *
     * If there was something listening for taht event,
     * trigger it and return it's return value.
     */
    args['onChange'] = (e) {
      boundValue[1](_getValueFromDom(e.target));
      if(onChange != null)
        return onChange(e);
    };
  }
}


/**
 * Convert event pack event handler into wrapper
 * and pass it only dart object of event
 * converted from JsObject of event.
 */
_convertEventHandlers(Map args) {
  var zone = Zone.current;
  args.forEach((key, value) {
    var eventFactory;
    if (_syntheticClipboardEvents.contains(key)) {
      eventFactory = syntheticClipboardEventFactory;
    } else if (_syntheticKeyboardEvents.contains(key)) {
      eventFactory = syntheticKeyboardEventFactory;
    } else if (_syntheticFocusEvents.contains(key)) {
      eventFactory = syntheticFocusEventFactory;
    } else if (_syntheticFormEvents.contains(key)) {
      eventFactory = syntheticFormEventFactory;
    } else if (_syntheticMouseEvents.contains(key)) {
      eventFactory = syntheticMouseEventFactory;
    } else if (_syntheticTouchEvents.contains(key)) {
      eventFactory = syntheticTouchEventFactory;
    } else if (_syntheticUIEvents.contains(key)) {
      eventFactory = syntheticUIEventFactory;
    } else if (_syntheticWheelEvents.contains(key)) {
      eventFactory = syntheticWheelEventFactory;
    } else return;
    args[key] = (JsObject e, [String domId]) => zone.run(() {
      value(eventFactory(e));
    });
  });
}

SyntheticEvent syntheticEventFactory(JsObject e) {
  return new SyntheticEvent(e["bubbles"], e["cancelable"], e["currentTarget"],
      e["defaultPrevented"], () => e.callMethod("preventDefault", []),
      () => e.callMethod("stopPropagation", []), e["eventPhase"], e["isTrusted"], e["nativeEvent"],
      e["target"], e["timeStamp"], e["type"]);
}

SyntheticEvent syntheticClipboardEventFactory(JsObject e) {
  return new SyntheticClipboardEvent(e["bubbles"], e["cancelable"], e["currentTarget"],
      e["defaultPrevented"], () => e.callMethod("preventDefault", []),
      () => e.callMethod("stopPropagation", []), e["eventPhase"], e["isTrusted"], e["nativeEvent"],
      e["target"], e["timeStamp"], e["type"], e["clipboardData"]);
}

SyntheticEvent syntheticKeyboardEventFactory(JsObject e) {
  return new SyntheticKeyboardEvent(e["bubbles"], e["cancelable"], e["currentTarget"],
      e["defaultPrevented"], () => e.callMethod("preventDefault", []),
      () => e.callMethod("stopPropagation", []), e["eventPhase"], e["isTrusted"],
      e["nativeEvent"], e["target"], e["timeStamp"], e["type"], e["altKey"],
      e["char"], e["charCode"], e["ctrlKey"], e["locale"], e["location"],
      e["key"], e["keyCode"], e["metaKey"], e["repeat"], e["shiftKey"]);
}

SyntheticEvent syntheticFocusEventFactory(JsObject e) {
  return new SyntheticFocusEvent(e["bubbles"], e["cancelable"], e["currentTarget"],
      e["defaultPrevented"], () => e.callMethod("preventDefault", []),
      () => e.callMethod("stopPropagation", []), e["eventPhase"], e["isTrusted"], e["nativeEvent"],
      e["target"], e["timeStamp"], e["type"], e["relatedTarget"]);
}

SyntheticEvent syntheticFormEventFactory(JsObject e) {
  return new SyntheticFormEvent(e["bubbles"], e["cancelable"], e["currentTarget"],
      e["defaultPrevented"], () => e.callMethod("preventDefault", []),
      () => e.callMethod("stopPropagation", []), e["eventPhase"], e["isTrusted"], e["nativeEvent"],
      e["target"], e["timeStamp"], e["type"]);
}

SyntheticEvent syntheticMouseEventFactory(JsObject e) {
  return new SyntheticMouseEvent(e["bubbles"], e["cancelable"], e["currentTarget"],
      e["defaultPrevented"], () => e.callMethod("preventDefault", []),
      () => e.callMethod("stopPropagation", []), e["eventPhase"], e["isTrusted"], e["nativeEvent"],
      e["target"], e["timeStamp"], e["type"], e["altKey"], e["button"], e["buttons"], e["clientX"], e["clientY"],
      e["ctrlKey"], e["metaKey"], e["pageX"], e["pageY"], e["relatedTarget"], e["screenX"],
      e["screenY"], e["shiftKey"]);
}

SyntheticEvent syntheticTouchEventFactory(JsObject e) {
  return new SyntheticTouchEvent(e["bubbles"], e["cancelable"], e["currentTarget"],
      e["defaultPrevented"], () => e.callMethod("preventDefault", []),
      () => e.callMethod("stopPropagation", []), e["eventPhase"], e["isTrusted"], e["nativeEvent"],
      e["target"], e["timeStamp"], e["type"], e["altKey"], e["changedTouches"], e["ctrlKey"], e["metaKey"],
      e["shiftKey"], e["targetTouches"], e["touches"]);
}

SyntheticEvent syntheticUIEventFactory(JsObject e) {
  return new SyntheticUIEvent(e["bubbles"], e["cancelable"], e["currentTarget"],
      e["defaultPrevented"], () => e.callMethod("preventDefault", []),
      () => e.callMethod("stopPropagation", []), e["eventPhase"], e["isTrusted"], e["nativeEvent"],
      e["target"], e["timeStamp"], e["type"], e["detail"], e["view"]);
}

SyntheticEvent syntheticWheelEventFactory(JsObject e) {
  return new SyntheticWheelEvent(e["bubbles"], e["cancelable"], e["currentTarget"],
      e["defaultPrevented"], () => e.callMethod("preventDefault", []),
      () => e.callMethod("stopPropagation", []), e["eventPhase"], e["isTrusted"], e["nativeEvent"],
      e["target"], e["timeStamp"], e["type"], e["deltaX"], e["deltaMode"], e["deltaY"], e["deltaZ"]);
}

Set _syntheticClipboardEvents = new Set.from(["onCopy", "onCut", "onPaste",]);

Set _syntheticKeyboardEvents = new Set.from(["onKeyDown", "onKeyPress", "onKeyUp",]);

Set _syntheticFocusEvents = new Set.from(["onFocus", "onBlur",]);

Set _syntheticFormEvents = new Set.from(["onChange", "onInput", "onSubmit",]);

Set _syntheticMouseEvents = new Set.from(["onClick", "onDoubleClick",
    "onDrag", "onDragEnd", "onDragEnter", "onDragExit", "onDragLeave",
    "onDragOver", "onDragStart", "onDrop", "onMouseDown", "onMouseEnter",
    "onMouseLeave", "onMouseMove", "onMouseOut", "onMouseOver", "onMouseUp",]);

Set _syntheticTouchEvents = new Set.from(["onTouchCancel", "onTouchEnd",
    "onTouchMove", "onTouchStart",]);

Set _syntheticUIEvents = new Set.from(["onScroll",]);

Set _syntheticWheelEvents = new Set.from(["onWheel",]);


Component _render(JsObject jsThis, HtmlElement element) {
  _React.callMethod('render', [jsThis, element]);
  var component;
  try {
    component = _getComponent(jsThis);
  } catch(e) {
    component = getDOMNode(jsThis);
  }
  return component;
}

bool _unmountComponentAtNode(HtmlElement element) {
  return _React.callMethod('unmountComponentAtNode', [element]);
}

void setClientConfiguration() {
  _React.callMethod('initializeTouchEvents', [true]);
  setReactConfiguration(_reactDom, _registerComponent, _render, null, _unmountComponentAtNode);
}
